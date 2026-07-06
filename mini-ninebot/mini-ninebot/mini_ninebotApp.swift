//
//  mini_ninebotApp.swift
//  mini-ninebot
//
//  Created by Jeff He on 2026/7/5.
//

import AppIntents
import SwiftUI

@main
struct mini_ninebotApp: App {
    init() {
        NinebotAppShortcutsProvider.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
