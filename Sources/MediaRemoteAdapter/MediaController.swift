import AppKit
import Foundation
internal import MediaRemoteAdapterCore

/// `@unchecked Sendable`: every field touched off the main queue is guarded by `stateLock` — the
/// stream state (`dataBuffer`, `dataBufferSearchStart`, `eventCount`), written by the pipe reader's
/// queue, and the listener (`listeningProcess`), read and written from main and the reader's
/// termination path. `lastTrackInfo` and the callbacks live on the main queue only. The controller
/// is created and driven from main.
///
/// Every call runs the vendored core (ungive/mediaremote-adapter, Vendor/) through `/usr/bin/perl`
/// and its script, bundled here as `run.pl`: the system perl is entitled to MediaRemote, this
/// process is not. The listener is `run.pl <image> stream`, a one-shot read is `get`, and each
/// command is its own child (`send`, `seek`, `shuffle`, `repeat`): ungive's `stream` takes no
/// commands on its stdin. No child is given this process's stdin.
public class MediaController: @unchecked Sendable {

    /// Test seams: the script and library the child perl runs. Production passes nil for both and
    /// gets the bundled `run.pl` and the image the core is linked into; tests point them at a
    /// fixture script.
    private let scriptPathOverride: String?
    private let libraryPathOverride: String?

    private var perlScriptPath: String? {
        if let scriptPathOverride { return scriptPathOverride }
        guard let path = Bundle.module.path(forResource: "run", ofType: "pl") else {
            assertionFailure("run.pl script not found in bundle resources.")
            return nil
        }
        return path
    }

    private var listeningProcess: Process?
    private var dataBuffer = Data()
    private var dataBufferSearchStart = 0
    private var lastTrackInfo: TrackInfo?
    private var eventCount = 0
    private let stateLock = NSLock()
    private let restartThreshold = 100
    private let commandQueue = DispatchQueue(label: "mediaremote-adapter.commands")
    /// The player's display name, looked up from its process (the core reports the PID and bundle
    /// identifier, not the name). A seam so the stream tests stay independent of what is running.
    let applicationName: @Sendable (pid_t) -> String?
    private static let sigpipeIgnored: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    public var onTrackInfoReceived: ((TrackInfo?) -> Void)?
    public var onListenerTerminated: (() -> Void)?
    public var onDecodingError: ((Error, Data) -> Void)?

    public init() {
        scriptPathOverride = nil
        libraryPathOverride = nil
        applicationName = MediaController.runningApplicationName
        _ = MediaController.sigpipeIgnored
    }

    init(scriptPath: String? = nil, libraryPath: String? = nil,
         applicationName: @escaping @Sendable (pid_t) -> String? = MediaController.runningApplicationName) {
        scriptPathOverride = scriptPath
        libraryPathOverride = libraryPath
        self.applicationName = applicationName
        _ = MediaController.sigpipeIgnored
    }

    @Sendable static func runningApplicationName(_ pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    /// The Mach-O image the vendored core is linked into: what the perl helper loads. Found from a
    /// core symbol's own address, so it is right however the consumer packaged this library (a
    /// framework from xcodebuild, a bare dylib from `swift build`, a test bundle).
    static let coreImagePath: String? = {
        let symbol: @convention(c) () -> Void = adapter_get
        var info = Dl_info()
        guard dladdr(unsafeBitCast(symbol, to: UnsafeRawPointer.self), &info) != 0,
              let name = info.dli_fname else { return nil }
        return String(cString: name)
    }()

    private var libraryPath: String? {
        if let libraryPathOverride { return libraryPathOverride }
        guard let path = Self.coreImagePath else {
            assertionFailure("Could not locate the image the MediaRemoteAdapter core is linked into.")
            return nil
        }
        return path
    }

    @discardableResult
    private func runPerlCommand(arguments: [String]) -> (output: String?, error: String?, terminationStatus: Int32) {
        guard let scriptPath = perlScriptPath else {
            return (nil, "Perl script not found.", -1)
        }
        guard let libraryPath = libraryPath else {
            return (nil, "Dynamic library path not found.", -1)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, libraryPath] + arguments

        process.standardInput = FileHandle.nullDevice
        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorPipe = Pipe()
        process.standardError = errorPipe

        // Locked box instead of captured vars: the readability handlers are @Sendable, and the
        // buffers were always mutated under `lock` — this makes the existing guard structural.
        final class PipeBuffers: @unchecked Sendable {
            let lock = NSLock()
            var output = Data()
            var error = Data()
        }
        let buffers = PipeBuffers()

        PipeReader.attach(outputPipe.fileHandleForReading) { [buffers] data in
            buffers.lock.lock()
            buffers.output.append(data)
            buffers.lock.unlock()
        }

        PipeReader.attach(errorPipe.fileHandleForReading) { [buffers] data in
            buffers.lock.lock()
            buffers.error.append(data)
            buffers.lock.unlock()
        }

        do {
            try process.run()
            process.waitUntilExit()

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            buffers.lock.lock()
            buffers.output.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            buffers.error.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            buffers.lock.unlock()

            let output = String(data: buffers.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = String(data: buffers.error, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return (output, errorOutput, process.terminationStatus)
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return (nil, error.localizedDescription, -1)
        }
    }

    public func getTrackInfo(_ onReceive: @escaping (TrackInfo?) -> Void) {
        guard let scriptPath = perlScriptPath else {
            onReceive(nil)
            return
        }
        guard let libraryPath = libraryPath else {
            onReceive(nil)
            return
        }

        // The completion is forwarded to the main queue inside every handler below.
        nonisolated(unsafe) let onReceive = onReceive
        let applicationName = self.applicationName
        let getProcess = Process()
        getProcess.executableURL = URL(fileURLWithPath: "/usr/bin/perl")

        // Locked state machine: the readability handler is @Sendable and fires on a private
        // queue; exactly-one-callback is enforced here rather than by closure-var discipline.
        final class LineState: @unchecked Sendable {
            let lock = NSLock()
            var buffer = Data()
            var searchStart = 0
            var callbackExecuted = false
        }
        let lineState = LineState()

        getProcess.arguments = [scriptPath, libraryPath] + CoreCLI.get

        getProcess.standardInput = FileHandle.nullDevice
        let outputPipe = Pipe()
        getProcess.standardOutput = outputPipe

        // `lineState` is captured STRONGLY by both closures: it is a local, so a weak capture let
        // it die the moment this function returned — the handler then returned without draining
        // the pipe (a 100% CPU spin per call) and the exit handler read "already delivered", so
        // the completion never ran at all. The "no line ever came" fallback runs at EOF, not at
        // process exit: exit can be observed before the last read, which delivered nil and then
        // the real line.
        PipeReader.attach(outputPipe.fileHandleForReading, onEOF: { [lineState] in
            lineState.lock.lock()
            let executed = lineState.callbackExecuted
            lineState.callbackExecuted = true
            lineState.lock.unlock()
            if !executed {
                DispatchQueue.main.async { onReceive(nil) }
            }
        }, onData: { [lineState] incomingData in

            // Deliver exactly one result on the main queue; guarded by the state machine's lock.
            func deliver(_ trackInfo: TrackInfo?) {
                DispatchQueue.main.async { onReceive(trackInfo) }
            }

            // First NON-EMPTY line wins; a blank line is skipped rather than consuming the one
            // delivery.
            var lineData: Data?
            lineState.lock.lock()
            lineState.buffer.append(incomingData)
            while !lineState.callbackExecuted,
                  let newlineData = "\n".data(using: .utf8),
                  let range = lineState.buffer.firstRange(of: newlineData, in: lineState.searchStart..<lineState.buffer.count) {
                let line = lineState.buffer.subdata(in: 0..<range.lowerBound)
                lineState.buffer.removeSubrange(0..<range.upperBound)
                lineState.searchStart = 0
                if !line.isEmpty {
                    lineData = line
                    lineState.callbackExecuted = true
                }
            }
            lineState.searchStart = lineState.buffer.count
            lineState.lock.unlock()

            guard let lineData else { return }
            // `get` prints the payload itself (no envelope), or `null` for "no player".
            deliver((try? CoreCLI.decodeGet(lineData))?.namingApplication(with: applicationName))
        })

        do {
            try getProcess.run()
        } catch {
            onReceive(nil)
        }
    }

    /// The listener's wire protocol: newline-delimited JSON from `run.pl stream` (`CoreCLI`), an
    /// empty payload for "no player". Internal so tests can replay recorded lines without a child
    /// process.
    func ingest(_ incomingData: Data) {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }

        self.dataBuffer.append(incomingData)

        guard let newlineData = "\n".data(using: .utf8) else { return }
        while let range = self.dataBuffer.firstRange(of: newlineData, in: self.dataBufferSearchStart..<self.dataBuffer.count) {
            guard range.lowerBound <= self.dataBuffer.count else {
                break
            }

            let lineData = self.dataBuffer.subdata(in: 0..<range.lowerBound)

            self.dataBuffer.removeSubrange(0..<range.upperBound)
            self.dataBufferSearchStart = 0

            guard !lineData.isEmpty else { continue }
            let trackInfo: TrackInfo?
            do {
                trackInfo = try CoreCLI.decodeStreamLine(lineData)?.namingApplication(with: applicationName)
            } catch {
                DispatchQueue.main.async {
                    self.onDecodingError?(error, lineData)
                }
                continue
            }
            // "No player" (an empty payload) is delivered as nil and is not counted: the count
            // measures the listener's track reports, which is what the restart threshold bounds.
            guard let trackInfo else {
                DispatchQueue.main.async {
                    self.onTrackInfoReceived?(nil)
                }
                continue
            }

            self.eventCount += 1
            // Decided HERE, under the lock that guards the count: the main-queue block below
            // must not read `eventCount` (this queue writes it). Exactly the event that reaches
            // the threshold restarts the listener; the restart resets the count.
            let restartDue = self.eventCount == self.restartThreshold
            DispatchQueue.main.async {
                let emitted = trackInfo.preservingArtwork(from: self.lastTrackInfo)
                self.lastTrackInfo = emitted
                self.onTrackInfoReceived?(emitted)

                if restartDue {
                    self.restartListeningProcess()
                }
            }
        }

        self.dataBufferSearchStart = self.dataBuffer.count
    }

    /// Runs one command as its own child, in call order. ungive's `stream` reads no commands, so
    /// unlike the old `run.pl loop` a live listener is never written to: every command spawns.
    func sendCommand(_ arguments: [String]) {
        guard !arguments.isEmpty else { return }
        commandQueue.async { [weak self] in
            _ = self?.runPerlCommand(arguments: arguments)
        }
    }
}

// The listener's lifecycle. An extension in this file (so it shares the class's private state)
// rather than the class body.
extension MediaController {

    public func startListening() {
        let idle = stateLock.withLock {
            guard listeningProcess == nil else { return false }
            eventCount = 0
            return true
        }
        guard idle else { return }
        startListeningInternal()
    }

    private func startListeningInternal() {
        guard let scriptPath = perlScriptPath else {
            return
        }
        guard let libraryPath = libraryPath else {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, libraryPath] + CoreCLI.stream

        // The core reads nothing from stdin; never hand it this process's own.
        process.standardInput = FileHandle.nullDevice

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        PipeReader.attach(outputPipe.fileHandleForReading) { [weak self] incomingData in
            self?.ingest(incomingData)
        }

        // Only the CURRENT listener's exit clears the slot: after a restart the old child's exit
        // arrives late and must not nil out its replacement.
        process.terminationHandler = { [weak self] exited in
            DispatchQueue.main.async {
                guard let self else { return }
                let report = self.stateLock.withLock {
                    guard self.listeningProcess === exited else { return false }
                    self.listeningProcess = nil
                    return self.eventCount != 0
                }
                if report {
                    self.onListenerTerminated?()
                }
            }
        }

        stateLock.withLock {
            listeningProcess = process
        }
        do {
            try process.run()
        } catch {
            print("Failed to start listening process: \(error)")
            stateLock.withLock {
                if listeningProcess === process {
                    listeningProcess = nil
                }
            }
        }
    }

    /// Detaches and stops the current listener and clears the stream state, under the lock; the
    /// caller decides whether a new one follows.
    private func tearDownListener(resetEventCount: Bool) {
        let process = stateLock.withLock {
            let process = listeningProcess
            listeningProcess = nil
            dataBuffer.removeAll()
            dataBufferSearchStart = 0
            if resetEventCount { eventCount = 0 }
            return process
        }
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
    }

    public func stopListening() {
        tearDownListener(resetEventCount: false)
    }

    private func restartListeningProcess() {
        tearDownListener(resetEventCount: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.startListeningInternal()
        }
    }
}
