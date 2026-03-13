import SwiftUI
import RiviumSync

struct BatchView: View {
    @State private var resultText = ""
    @State private var isRunning = false

    private let collection = RiviumSync.shared.database(AppConfig.databaseId).collection(AppConfig.todosCollection)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    GroupBox("Batch Operations") {
                        VStack(spacing: 12) {
                            Text("Execute multiple operations atomically")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                batchCreate()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.square.on.square")
                                    Text("Batch Create (3 docs)")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(isRunning)

                            Button {
                                batchUpdate()
                            } label: {
                                HStack {
                                    Image(systemName: "pencil.circle")
                                    Text("Batch Update All")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(isRunning)

                            Button {
                                batchDeleteCompleted()
                            } label: {
                                HStack {
                                    Image(systemName: "trash.circle")
                                    Text("Batch Delete Completed")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .disabled(isRunning)

                            Button {
                                batchMixed()
                            } label: {
                                HStack {
                                    Image(systemName: "square.stack.3d.up.fill")
                                    Text("Mixed Batch (Create + Update + Delete)")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunning)
                        }
                        .padding(.top, 8)
                    }

                    if isRunning {
                        ProgressView("Running batch...")
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
            .navigationTitle("Batch")
        }
    }

    private func batchCreate() {
        isRunning = true
        Task {
            do {
                let batch = RiviumSync.shared.batch()
                for i in 1...3 {
                    batch.create(collection, data: [
                        "title": "Batch Task \(i)",
                        "completed": false,
                        "createdAt": ISO8601DateFormatter().string(from: Date())
                    ])
                }
                try await batch.commit()
                await MainActor.run {
                    resultText = "Created 3 documents atomically"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    resultText = "Error: \(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    private func batchUpdate() {
        isRunning = true
        Task {
            do {
                let docs = try await collection.getAll()
                let syncedDocs = docs.filter { !$0.id.hasPrefix("local_") }
                guard !syncedDocs.isEmpty else {
                    await MainActor.run {
                        resultText = "No documents to update"
                        isRunning = false
                    }
                    return
                }

                let batch = RiviumSync.shared.batch()
                for doc in syncedDocs {
                    batch.update(collection, documentId: doc.id, data: [
                        "batchUpdated": true,
                        "updatedAt": ISO8601DateFormatter().string(from: Date())
                    ])
                }
                try await batch.commit()
                await MainActor.run {
                    resultText = "Updated \(syncedDocs.count) documents"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    resultText = "Error: \(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    private func batchDeleteCompleted() {
        isRunning = true
        Task {
            do {
                let docs = try await collection.getAll()
                let completed = docs.filter {
                    !$0.id.hasPrefix("local_") && ($0.data["completed"]?.value as? Bool ?? false)
                }
                guard !completed.isEmpty else {
                    await MainActor.run {
                        resultText = "No completed documents to delete"
                        isRunning = false
                    }
                    return
                }

                let batch = RiviumSync.shared.batch()
                for doc in completed {
                    batch.delete(collection, documentId: doc.id)
                }
                try await batch.commit()
                await MainActor.run {
                    resultText = "Deleted \(completed.count) completed documents"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    resultText = "Error: \(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    private func batchMixed() {
        isRunning = true
        Task {
            do {
                let docs = try await collection.getAll()
                let syncedDocs = docs.filter { !$0.id.hasPrefix("local_") }

                let batch = RiviumSync.shared.batch()

                // Create one
                batch.create(collection, data: [
                    "title": "Mixed Batch New",
                    "completed": false,
                    "createdAt": ISO8601DateFormatter().string(from: Date())
                ])

                // Update first
                if let first = syncedDocs.first {
                    batch.update(collection, documentId: first.id, data: [
                        "mixedBatch": true
                    ])
                }

                // Delete last
                if let last = syncedDocs.last, syncedDocs.count > 1 {
                    batch.delete(collection, documentId: last.id)
                }

                try await batch.commit()
                await MainActor.run {
                    resultText = "Mixed batch committed: 1 create, 1 update, 1 delete"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    resultText = "Error: \(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }
}
