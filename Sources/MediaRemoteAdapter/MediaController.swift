import Foundation

/// `@unchecked Sendable`: every field touched off the main queue is guarded by `stateLock` — the
/// stream state (`dataBuffer`, `dataBufferSearchStart`, `eventCount`), written by the pipe reader's
/// queue, and the listener (`listeningProcess`, `listeningInputPipe`), read by `commandQueue`.
/// `lastTrackInfo` and the callbacks live on the main queue only. The controller is created and
/// driven from main.
public class MediaController: @unchecked Sendable {

    /// Test seams: the script and library the child perl runs. Production passes nil for both and
    /// gets the bundled `run.pl` and this framework's dylib; tests point them at a fixture script.
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
    private var listeningInputPipe: Pipe?
    private var dataBuffer = Data()
    private var dataBufferSearchStart = 0
    private var lastTrackInfo: TrackInfo?
    private var eventCount = 0
    private let stateLock = NSLock()
    private let restartThreshold = 100
    private let commandQueue = DispatchQueue(label: "mediaremote-adapter.commands")
    private static let sigpipeIgnored: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    public var onTrackInfoReceived: ((TrackInfo?) -> Void)?
    public var onListenerTerminated: (() -> Void)?
    public var onDecodingError: ((Error, Data) -> Void)?

    public init() {
        scriptPathOverride = nil
        libraryPathOverride = nil
        _ = MediaController.sigpipeIgnored
    }

    init(scriptPath: String, libraryPath: String) {
        scriptPathOverride = scriptPath
        libraryPathOverride = libraryPath
        _ = MediaController.sigpipeIgnored
    }

    private var libraryPath: String? {
        if let libraryPathOverride { return libraryPathOverride }
        let bundle = Bundle(for: MediaController.self)
        guard let path = bundle.executablePath else {
            assertionFailure("Could not locate the executable path for the MediaRemoteAdapter framework.")
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

        getProcess.arguments = [scriptPath, libraryPath, "get"]

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
            if lineData == "NIL".data(using: .utf8) {
                deliver(nil)
                return
            }
            do {
                deliver(try JSONDecoder().decode(TrackInfo.self, from: lineData))
            } catch {
                deliver(nil)
            }
        })

        do {
            try getProcess.run()
        } catch {
            onReceive(nil)
        }
    }

    /// The listener's wire protocol: newline-delimited JSON from `run.pl loop`, `NIL` for "no
    /// player". Internal so tests can replay recorded lines without a child process.
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

            if lineData == "NIL".data(using: .utf8) {
                DispatchQueue.main.async {
                    self.onTrackInfoReceived?(nil)
                }
                continue
            }

            if !lineData.isEmpty {
                self.eventCount += 1
                // Decided HERE, under the lock that guards the count: the main-queue block below
                // must not read `eventCount` (this queue writes it). Exactly the event that reaches
                // the threshold restarts the listener; the restart resets the count.
                let restartDue = self.eventCount == self.restartThreshold

                do {
                    let trackInfo = try JSONDecoder().decode(TrackInfo.self, from: lineData)
                    DispatchQueue.main.async {
                        let emitted = trackInfo.preservingArtwork(from: self.lastTrackInfo)
                        self.lastTrackInfo = emitted
                        self.onTrackInfoReceived?(emitted)

                        if restartDue {
                            self.restartListeningProcess()
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onDecodingError?(error, lineData)
                    }
                }
            }
        }

        self.dataBufferSearchStart = self.dataBuffer.count
    }

    func sendCommand(_ arguments: [String]) {
        guard !arguments.isEmpty else { return }
        let line = arguments.joined(separator: " ") + "\n"
        guard let data = line.data(using: .utf8) else { return }

        commandQueue.async { [weak self] in
            guard let self = self else { return }
            let (listener, listenerInput) = self.stateLock.withLock { (self.listeningProcess, self.listeningInputPipe) }
            if let process = listener,
               process.isRunning,
               let pipe = listenerInput {
                let handle = pipe.fileHandleForWriting
                do {
                    if #available(macOS 10.15.4, *) {
                        try handle.write(contentsOf: data)
                    } else {
                        handle.write(data)
                    }
                    return
                } catch {
                    // Pipe closed under us; fall through to spawn.
                }
            }
            _ = self.runPerlCommand(arguments: arguments)
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
        process.arguments = [scriptPath, libraryPath, "loop"]

        let inputPipe = Pipe()
        process.standardInput = inputPipe

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
                    self.listeningInputPipe = nil
                    return self.eventCount != 0
                }
                if report {
                    self.onListenerTerminated?()
                }
            }
        }

        stateLock.withLock {
            listeningProcess = process
            listeningInputPipe = inputPipe
        }
        do {
            try process.run()
        } catch {
            print("Failed to start listening process: \(error)")
            stateLock.withLock {
                if listeningProcess === process {
                    listeningProcess = nil
                    listeningInputPipe = nil
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
            listeningInputPipe = nil
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
