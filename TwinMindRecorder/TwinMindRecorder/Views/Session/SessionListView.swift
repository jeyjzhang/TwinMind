import SwiftUI
import SwiftData

struct SessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [RecordingSession]
    @EnvironmentObject var transcriptionService: AudioTranscriptionService
    
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !transcriptionService.isOnline {
                    HStack {
                        Label("Offline mode — queued segments will retry", systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.2))
                }

                List {
                    ForEach(sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowView(session: session)
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
                .listStyle(.plain)
                .navigationTitle("Sessions")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showDeleteAllConfirmation = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
                .confirmationDialog("Are you sure you want to delete all sessions?", isPresented: $showDeleteAllConfirmation) {
                    Button("Delete All", role: .destructive) {
                        deleteAllSessions()
                    }
                    Button("Cancel", role: .cancel) { }
                }
                .onAppear {
                    Task {
                        transcriptionService.setModelContext(modelContext)
                        transcriptionService.retryPendingSegments(from: sessions)
                        transcriptionService.startNetworkMonitor(sessions: sessions)
                    }
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
    private func deleteAllSessions() {
        for session in sessions {
            modelContext.delete(session)
        }
        
        do {
            try modelContext.save()
            print("🗑️ All sessions deleted")
        } catch {
            print("❌ Failed to delete all sessions: \(error)")
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
