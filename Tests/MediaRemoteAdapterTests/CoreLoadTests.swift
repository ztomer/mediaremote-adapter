import Darwin
import Foundation
import XCTest
@testable import MediaRemoteAdapter

/// The vendored core is linked INTO the consumer's process (it shares an image with the Swift
/// layer, so the perl helper can load that image), but upstream wrote it to be loaded only by its
/// own perl script: its load-time constructors installed SIGINT/SIGTERM handlers that stop the
/// loading thread's run loop, and loaded the private framework with `exit(1)` on failure. In a
/// host app that is a SIGTERM that no longer quits and a fatal path reachable from `dyld`.
/// Vendored patch 0002 moves both to first use. This test is the signal half of its proof, run in
/// a process that has loaded the core and never called it. (The private framework half cannot be
/// seen from here: AppKit loads MediaRemote into every test process anyway. tools/repo_gates.sh
/// reads the core's object code instead: only the allowlisted objects carry a load-time
/// initializer.)
final class CoreLoadTests: XCTestCase {

    private func disposition(_ signal: Int32) -> UnsafeMutableRawPointer? {
        var current = sigaction()
        sigaction(signal, nil, &current)
        return unsafeBitCast(current.__sigaction_u.__sa_handler, to: UnsafeMutableRawPointer?.self)
    }

    func testLoadingTheCoreInstallsNoSignalHandler() {
        XCTAssertTrue(MediaController.coreImagePath != nil, "the core must be linked into this process")
        for signal in [SIGINT, SIGTERM] {
            XCTAssertNil(disposition(signal), "signal \(signal) has a handler the host never installed")
        }
    }
}
