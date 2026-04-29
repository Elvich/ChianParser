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

        // Explicit store URL so we can delete it on migration failure
        let storeURL = URL.applicationSupportDirectory
            .appending(path: "ChianParser", directoryHint: .isDirectory)
            .appending(path: "apartments.store")
        let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema changed (new fields added) and automatic migration failed.
            // During development: delete the old store and start fresh.
            // TODO: replace with VersionedSchema + SchemaMigrationPlan before App Store release.
            print("⚠️ SwiftData migration failed — recreating store. All data will be lost: \(error)")
            let filesToDelete = [storeURL, storeURL.appendingPathExtension("shm"), storeURL.appendingPathExtension("wal")]
            filesToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after store reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(container)
        .modelContainer(sharedModelContainer)

        // Standard macOS Settings window — opens via Cmd+, or app menu
        Settings {
            SettingsView()
        }
        .environment(container)
        .modelContainer(sharedModelContainer)
    }
}
