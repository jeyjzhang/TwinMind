//
//  SessionListView.swift
//  TwinMindRecorder
//
//  Created by Jerry Zhang on 2025-07-02.
//

import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [RecordingSession]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(sessions) { session in
                    SessionRowView(session: session)
                }
                .onDelete(perform: deleteSessions)
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }
    
    private func deleteSessions(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(sessions[index])
            }
        }
    }
}

struct SessionRowView: View {
    let session: RecordingSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title ?? "Untitled Session")
                .font(.headline)
            
            Text(session.startTime, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Duration: \(formatDuration(session.totalDuration))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}

#Preview {
    SessionListView()
}
