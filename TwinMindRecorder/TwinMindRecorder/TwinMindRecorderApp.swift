//
//  TwinMindRecorderApp.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import SwiftUI
import SwiftData

@main
struct TwinMindRecorderApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RecordingSession.self,
            AudioSegment.self,
            Transcription.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        let buildKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String
        print("🧪 Build-time API key: \(buildKey ?? "nil")")

        if let key = buildKey {
            try? KeychainManager.saveAPIKey(key)
        }
    }



    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AudioTranscriptionService())
            
        }
        .modelContainer(sharedModelContainer)
    }
}
