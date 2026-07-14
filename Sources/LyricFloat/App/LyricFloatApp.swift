import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct LyricFloatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label(model.shortTrackTitle, systemImage: "quote.bubble.fill")
                .onAppear(perform: model.start)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }

        Window("选择歌词版本", id: "lyrics-candidates") {
            LyricsCandidateSelectionView(model: model)
        }
        .defaultSize(width: 720, height: 560)
    }
}
