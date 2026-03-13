import SwiftUI
import RiviumSync

struct OfflineView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @State private var resultText = ""

    private let collection = RiviumSync.shared.database(AppConfig.databaseId).collection(AppConfig.todosCollection)

    var syncStateColor: Color {
        switch connectionManager.syncState {
        case .idle: return .green
        case .syncing: return .blue
        case .offline: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Status Card
                    GroupBox("Status") {
                        VStack(spacing: 12) {
                            StatusRow(
                                label: "Connection",
                                value: connectionManager.isConnected ? "Connected" : "Disconnected",
                                color: connectionManager.isConnected ? .green : .orange
                            )

                            StatusRow(
                                label: "Sync State",
                                value: syncStateString,
                                color: syncStateColor
                            )

                            StatusRow(
                                label: "Pending",
                                value: "\(connectionManager.pendingCount)",
                                color: connectionManager.pendingCount > 0 ? .orange : .green
                            )

                            StatusRow(
                                label: "Offline Mode",
                                value: RiviumSync.shared.isOfflineEnabled ? "Enabled" : "Disabled",
                                color: RiviumSync.shared.isOfflineEnabled ? .green : .gray
                            )
                        }
                        .padding(.top, 8)
                    }

                    // Actions
                    GroupBox("Actions") {
                        VStack(spacing: 12) {
                            Button {
                                createOfflineDoc()
                            } label: {
                                HStack {
                                    Image(systemName: "doc.badge.plus")
                                    Text("Create Document")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                            Button {
                                readDocuments()
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text.magnifyingglass")
                                    Text("Read Documents")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                RiviumSync.shared.forceSyncNow()
                                resultText = "Force sync triggered"
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Force Sync")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            .disabled(connectionManager.pendingCount == 0)

                            Button {
                                RiviumSync.shared.clearOfflineCache()
                                resultText = "Cache cleared"
                            } label: {
                                HStack {
                                    Image(systemName: "xmark.bin")
                                    Text("Clear Cache")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(.top, 8)
                    }

                    if !resultText.isEmpty {
                        GroupBox("Result") {
                            Text(resultText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Offline")
        }
    }

    private var syncStateString: String {
        switch connectionManager.syncState {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .offline: return "Offline"
        case .error: return "Error"
        }
    }

    private func createOfflineDoc() {
        Task {
            do {
                let doc = try await collection.add(data: [
                    "title": "Offline Test \(Int.random(in: 100...999))",
                    "isConnected": connectionManager.isConnected,
                    "createdAt": ISO8601DateFormatter().string(from: Date())
                ])
                let status = connectionManager.isConnected ? "Online - synced" : "Offline - queued"
                await MainActor.run {
                    resultText = "Created: \(doc.id.prefix(20))...\n\(status)"
                }
            } catch {
                await MainActor.run { resultText = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func readDocuments() {
        Task {
            do {
                let docs = try await collection.getAll()
                let preview = docs.prefix(5).map { doc -> String in
                    let title = doc.data["title"]?.value as? String ?? "untitled"
                    let prefix = doc.id.hasPrefix("local_") ? "[local] " : ""
                    return "- \(prefix)\(title)"
                }.joined(separator: "\n")
                let more = docs.count > 5 ? "\n... and \(docs.count - 5) more" : ""
                await MainActor.run {
                    resultText = "Read \(docs.count) documents:\n\(preview)\(more)"
                }
            } catch {
                await MainActor.run { resultText = "Error: \(error.localizedDescription)" }
            }
        }
    }
}

struct StatusRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
    }
}
