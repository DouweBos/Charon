// App/CharonApp.swift
// Charon

import SwiftUI

@main
struct CharonApp: App {
    @State private var model: AppModel

    init() {
        AppSettings.registerDefaults()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        Window("Charon", id: "main") {
            RootView()
                .environment(model)
                .environment(model.navigator)
                .environment(model.volumes)
                .environment(model.analyze)
                .environment(model.offload)
                .environment(model.stats)
                .environment(model.collector)
                .environment(model.clean)
                .environment(model.uninstall)
                .environment(model.optimize)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CharonCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
