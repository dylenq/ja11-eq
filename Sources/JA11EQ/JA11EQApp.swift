import AppKit
import JA11EQCore
import SwiftUI

@main
struct JA11EQApp: App {
    @State private var model = AppModel.live()

    init() {
        // A plain SwiftPM executable is not an .app bundle: without this the window opens behind
        // the terminal and the process has no Dock presence or focus.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        Window("JA11 EQ", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 560)
                .task {
                    NSApp.activate(ignoringOtherApps: true)
                    model.start()
                }
        }
    }
}
