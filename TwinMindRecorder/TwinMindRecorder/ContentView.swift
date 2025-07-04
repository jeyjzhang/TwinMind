//
//  ContentView.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            RecordingView()
                .tabItem {
                    Image(systemName: "mic.circle")
                    Text("Record")
                }
            
            SessionListView()
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Sessions")
                }
        }
    }
}

#Preview {
    ContentView()
}
