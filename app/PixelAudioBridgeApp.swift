import SwiftUI

/// Stops the bridge when the app quits, so audio never outlives the app.
/// Also keeps the app resident when its window is closed. The menu bar item
/// stays live, and closing the window should not silence playback.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        BridgeController.shared.onLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Must block: returning early would let the app exit while scrcpy and
        // mpv are still alive, leaving audio playing with no way to stop it.
        BridgeController.shared.stopBlocking()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct PixelAudioBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var bridge = BridgeController.shared

    var body: some Scene {
        Window("Pixel Audio Bridge", id: "main") {
            ContentView()
                .environmentObject(bridge)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }   // no New Window item
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(bridge)
        } label: {
            Image(systemName: bridge.menuBarSymbol)
        }
    }
}
