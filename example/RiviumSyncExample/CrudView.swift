import SwiftUI
import RiviumSync

struct CrudView: View {
    @State private var title = ""
    @State private var description = ""
    @State private var documents: [SyncDocument] = []
    @State private var resultText = ""
    @State private var isLoading = false

    private let collection = RiviumSync.shared.database(AppConfig.databaseId).collection(AppConfig.todosCollection)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Create Section
                    GroupBox("Create Document") {
                        VStack(spacing: 12) {
                            TextField("Title", text: $title)
                                .textFieldStyle(.roundedBorder)
                            TextField("Description", text: $description)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                createDocument()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(title.isEmpty)
                        }
                        .padding(.top, 8)
                    }

                    // Documents List
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Documents")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    loadDocuments()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }

                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else if documents.isEmpty {
                                Text("No documents yet. Create one above!")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                ForEach(documents, id: \.id) { doc in
                                    DocumentRow(
                                        doc: doc,
                                        onToggle: { toggleComplete(doc) },
                                        onDelete: { deleteDocument(doc.id) }
                                    )
                                }
                            }
                        }
                    }

                    // Result
                    if !resultText.isEmpty {
                        GroupBox("Last Result") {
                            Text(resultText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("CRUD")
            .onAppear { loadDocuments() }
        }
    }

    private func createDocument() {
        let docTitle = title
        let docDesc = description
        title = ""
        description = ""

        Task {
            do {
                let doc = try await collection.add(data: [
                    "title": docTitle,
                    "description": docDesc,
                    "completed": false,
                    "createdAt": ISO8601DateFormatter().string(from: Date())
                ])
                await MainActor.run {
                    resultText = "Created: \(doc.id)"
                    loadDocuments()
                }
            } catch {
                await MainActor.run { resultText = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func loadDocuments() {
        isLoading = true
        Task {
            do {
                let docs = try await collection.getAll()
                await MainActor.run {
                    documents = docs.filter { !$0.id.hasPrefix("local_") }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    resultText = "Error loading: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func toggleComplete(_ doc: SyncDocument) {
        let isCompleted = doc.data["completed"]?.value as? Bool ?? false
        Task {
            do {
                _ = try await collection.update(documentId: doc.id, data: [
                    "completed": !isCompleted
                ])
                await MainActor.run { loadDocuments() }
            } catch {
                await MainActor.run { resultText = "Error: \(error.localizedDescription)" }
            }
        }
    }

    private func deleteDocument(_ id: String) {
        Task {
            do {
                try await collection.delete(documentId: id)
                await MainActor.run {
                    resultText = "Deleted: \(id)"
                    loadDocuments()
                }
            } catch {
                await MainActor.run { resultText = "Error: \(error.localizedDescription)" }
            }
        }
    }
}

struct DocumentRow: View {
    let doc: SyncDocument
    let onToggle: () -> Void
    let onDelete: () -> Void

    var title: String { doc.data["title"]?.value as? String ?? "Untitled" }
    var isCompleted: Bool { doc.data["completed"]?.value as? Bool ?? false }

    var body: some View {
        HStack {
            Button { onToggle() } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading) {
                Text(title)
                    .strikethrough(isCompleted)
                    .foregroundColor(isCompleted ? .secondary : .primary)
                Text(doc.id.prefix(12) + "...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button { onDelete() } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
