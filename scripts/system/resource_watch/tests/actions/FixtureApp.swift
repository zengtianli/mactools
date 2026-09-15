import Cocoa

// This app has no window and is launched with activates=false. It only accepts
// normal termination requests and writes receipts inside its private fixture dir.
let fixtureDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        try? Data("ready".utf8).write(to: fixtureDirectory.appendingPathComponent("ready"))
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        try? Data("received".utf8).write(to: fixtureDirectory.appendingPathComponent("quit-request"))
        return FileManager.default.fileExists(atPath: fixtureDirectory.appendingPathComponent("refuse").path) ? .terminateCancel : .terminateNow
    }
}
let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
// A test interruption cannot leave a persistent app, including a refusing one.
Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { _ in exit(0) }
app.run()
