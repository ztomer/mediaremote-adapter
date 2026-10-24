import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// A stand-in for `run.pl`: the same argv contract (`<script> <library> <command> [args]`, run by
/// `/usr/bin/perl`), but it replays canned stdout instead of loading the private framework.
///
/// The "library" argument is repurposed as the fixture's log path, so every spawn is observable:
///   - `argv <command> [args]` is appended for each launch
///   - for `get`/`loop` the contents of `<log>.out` are printed
///   - `loop` with `<log>.hold` present then reads stdin to EOF, logging `stdin <line>` per line
///     (a live listener taking commands); without `.hold` it exits, as a crashed listener would.
final class FixtureProcess {
    let directory: URL
    let scriptPath: String
    let logPath: String

    private static let script = """
    use strict; use warnings;
    $| = 1;
    my ($log_path, $cmd, @args) = @ARGV;
    open(my $log, '>>', $log_path) or die "log: $!";
    select((select($log), $| = 1)[0]);
    print $log join(' ', 'argv', $cmd, @args), "\\n";
    if ($cmd eq 'get' || $cmd eq 'loop') {
        if (open(my $fh, '<', "$log_path.out")) { print $_ while <$fh>; close $fh; }
    }
    if ($cmd eq 'loop' && -e "$log_path.hold") {
        while (my $line = <STDIN>) { chomp $line; print $log "stdin $line\\n"; }
    }
    """

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mra-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        scriptPath = directory.appendingPathComponent("run.pl").path
        logPath = directory.appendingPathComponent("log").path
        try Self.script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try Data().write(to: URL(fileURLWithPath: logPath))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func controller() -> MediaController {
        MediaController(scriptPath: scriptPath, libraryPath: logPath)
    }

    /// What the next `get`/`loop` prints.
    func setOutput(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(toFile: logPath + ".out", atomically: true, encoding: .utf8)
    }

    /// Make `loop` stay alive reading commands from stdin until EOF or SIGTERM.
    func holdLoopOpen() throws {
        try Data().write(to: URL(fileURLWithPath: logPath + ".hold"))
    }

    var logLines: [String] {
        let text = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// Spins the main run loop (callbacks are delivered there) until `condition`, or fails.
    @discardableResult
    func waitUntil(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                   _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what); fixture log: \(logLines)", file: file, line: line)
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return true
    }
}
