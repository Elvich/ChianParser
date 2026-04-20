//
//  ChianParserApp.swift
//  ChianParser
//
//  Created by Maksim on 30.03.2026.
//

import SwiftUI
import SwiftData

@main
struct ChianParserApp: App {
    let container = AppContainer()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Apartment.self,
            PricePoint.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(container)
        .modelContainer(sharedModelContainer)
    }
}
