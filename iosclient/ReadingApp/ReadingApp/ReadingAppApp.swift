//
//  ReadingAppApp.swift
//  ReadingApp
//
//  Created by wang on 2025/11/26.
//

import SwiftUI

@main
struct ReadingAppApp: App {
    init() {
        UserScopedStorage.activateCurrentUserScope()
    }

    private var previewScreen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--reading-screen"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--reading-experience") {
                ReadingChallengeView(initialScreen: previewScreen)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
