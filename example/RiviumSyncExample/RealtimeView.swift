import SwiftUI
import RiviumSync

struct RealtimeView: View {
    @State private var isListening = false
    @State private var events: [EventLog] = []
    @State private var resultText = ""
    @State private var previousDocs: [SyncDocument] = []

    private let collection = RiviumSync.shared.database(AppConfig.databaseId).collection(AppConfig.todosCollection)

    struct EventLog: Identifiable {
        let id = UUID()
        let type: String
        let message: String
        let time: Date

        var color: Color {
            switch type {
            case "create": return .green
            case "update": return .orange
            case "delete": return .red
            default: return .blue
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Listener Control
                    GroupBox {
                        VStack(spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(isListening ? .green : .gray)
                                    .frame(width: 10, height: 10)
                                Text(isListening ? "Listening for changes" : "Listener inactive")
                                    .font(.subheadline)
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                Button {
                                    startListener()
                                } label: {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Start")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(isListening)

                                Button {
                                    stopListener()
                                } label: {
                                    HStack {
                                        Image(systemName: "stop.fill")
                                        Text("Stop")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .disabled(!isListening)
                            }
                        }
                    }

                    // Event Log
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Event Log")
                                    .font(.headline)
                                Spacer()
                                if !events.isEmpty {
                                    Button("Clear") {
                                        events.removeAll()
                                    }
                                    .font(.caption)
                                }
                            }

                            if events.isEmpty {
                                Text("Start the listener and make changes to see events here.")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .padding(.vertical, 20)
                                    .frame(maxWidth: .infinity)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(events.reversed()) { event in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(event.type.uppercased())
                                                .font(.system(.caption2, design: .monospaced))
                                                .fontWeight(.bold)
                                                .foregroundColor(event.color)
                                                .frame(width: 55, alignment: .leading)
                                            Text(event.message)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundColor(.primary)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }

                    // Test Actions
                    GroupBox("Test Actions") {
                        VStack(spacing: 12) {
                            Text("Trigger changes to test realtime listener")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                Button {
                                    testCreate()
                                } label: {
                                    VStack {
                                        Image(systemName: "plus.circle")
                                        Text("Create")
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)

                                Button {
                                    testUpdate()
                                } label: {
                                    VStack {
                                        Image(systemName: "pencil.circle")
                                        Text("Update")
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)

                                Button {
                                    testDelete()
                                } label: {
                                    VStack {
                                        Image(systemName: "trash.circle")
                                        Text("Delete")
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                        }
                        .padding(.top, 8)
                    }

                    if !resultText.isEmpty {
                        GroupBox("Info") {
                            Text(resultText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Realtime")
            .onDisappear { stopListener() }
        }
    }

    private func startListener() {
        addEvent("info", "Starting listener...")

        // Start the MQTT-based listener (works when MQTT is connected)
        let col = collection
        _ = col.listen { docs in
            processDocChanges(docs)
        }

        // Initial fetch
        Task {
            do {
                let docs = try await col.getAll()
                await MainActor.run {
                    previousDocs = docs
                    addEvent("info", "Loaded \(docs.count) documents")
                }
            } catch {
                await MainActor.run {
                    addEvent("info", "Failed to load: \(error.localizedDescription)")
                }
            }
        }

        isListening = true
        addEvent("info", "Listener started")
    }

    private func processDocChanges(_ docs: [SyncDocument]) {
        let newIds = Set(docs.map { $0.id })
        let prevIds = Set(previousDocs.map { $0.id })

        var hasChanges = false

        // Detect creates
        for doc in docs where !prevIds.contains(doc.id) {
            let title = doc.data["title"]?.value as? String ?? doc.id
            addEvent("create", title)
            hasChanges = true
        }

        // Detect deletes
        for doc in previousDocs where !newIds.contains(doc.id) {
            let title = doc.data["title"]?.value as? String ?? doc.id
            addEvent("delete", title)
            hasChanges = true
        }

        // Detect updates
        for doc in docs where prevIds.contains(doc.id) {
            if let prev = previousDocs.first(where: { $0.id == doc.id }),
               prev.version != doc.version {
                let title = doc.data["title"]?.value as? String ?? doc.id
                addEvent("update", title)
                hasChanges = true
            }
        }

        if hasChanges || previousDocs.isEmpty {
            previousDocs = docs
        }
    }

    private func stopListener() {
        listener?.remove()
        listener = nil
        isListening = false
        previousDocs = []
        addEvent("info", "Listener stopped")
    }

    @State private var listener: ListenerRegistration?

    private func addEvent(_ type: String, _ message: String) {
        let event = EventLog(type: type, message: message, time: Date())
        events.append(event)
        if events.count > 50 { events.removeFirst() }
    }

    private func testCreate() {
        Task {
            do {
                let doc = try await collection.add(data: [
                    "title": "Realtime Test \(Int.random(in: 100...999))",
                    "completed": false,
                    "createdAt": ISO8601DateFormatter().string(from: Date())
                ])
                await MainActor.run { resultText = "Created: \(doc.id.prefix(16))..." }
            } catch {
                await MainActor.run { resultText = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func testUpdate() {
        Task {
            do {
                let docs = try await collection.getAll()
                let syncedDocs = docs.filter { !$0.id.hasPrefix("local_") }
                guard let doc = syncedDocs.first else {
                    await MainActor.run { resultText = "No documents to update" }
                    return
                }
                _ = try await collection.update(documentId: doc.id, data: [
                    "realtimeUpdated": true,
                    "updatedAt": ISO8601DateFormatter().string(from: Date())
                ])
                await MainActor.run { resultText = "Updated: \(doc.id.prefix(16))..." }
            } catch {
                await MainActor.run { resultText = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func testDelete() {
        Task {
            do {
                let docs = try await collection.getAll()
                let syncedDocs = docs.filter { !$0.id.hasPrefix("local_") }
                guard let doc = syncedDocs.last else {
                    await MainActor.run { resultText = "No documents to delete" }
                    return
                }
                try await collection.delete(documentId: doc.id)
                await MainActor.run { resultText = "Deleted: \(doc.id.prefix(16))..." }
            } catch {
                await MainActor.run { resultText = "Error: \(error.localizedDescription)" }
            }
        }
    }
}
