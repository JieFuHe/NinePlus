//
//  mini_ninebotApp.swift
//  mini-ninebot
//

import AppIntents
import SwiftUI

@main
struct mini_ninebotApp: App {
    @UIApplicationDelegateAdaptor(NinebotPushManager.self) private var pushManager

    init() {
        NinebotAppShortcutsProvider.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
