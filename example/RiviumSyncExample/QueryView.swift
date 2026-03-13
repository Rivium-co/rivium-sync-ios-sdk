import SwiftUI
import RiviumSync

struct QueryView: View {
    @State private var field = "completed"
    @State private var value = "true"
    @State private var limitCount = "10"
    @State private var results: [SyncDocument] = []
    @State private var resultText = ""
    @State private var isLoading = false

    private let collection = RiviumSync.shared.database(AppConfig.databaseId).collection(AppConfig.todosCollection)

    let operators = ["==", "!=", ">", ">=", "<", "<="]
    @State private var selectedOp = "=="

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Query Builder
                    GroupBox("Build Query") {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                TextField("Field", text: $field)
                                    .textFieldStyle(.roundedBorder)

                                Picker("Op", selection: $selectedOp) {
                                    ForEach(operators, id: \.self) { op in
                                        Text(op).tag(op)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 70)

                                TextField("Value", text: $value)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("Limit:")
                                    .font(.subheadline)
                                TextField("10", text: $limitCount)
                                    .textFieldStyle(.roundedBorder)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    #endif
                                    .frame(width: 60)
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                Button {
                                    runQuery()
                                } label: {
                                    HStack {
                                        Image(systemName: "magnifyingglass")
                                        Text("Query")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                Button {
                                    loadAll()
                                } label: {
                                    HStack {
                                        Image(systemName: "list.bullet")
                                        Text("Get All")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.top, 8)
                    }

                    // Results
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Results (\(results.count))")
                                .font(.headline)

                            if isLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else if results.isEmpty {
                                Text("No results. Run a query above.")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                ForEach(results, id: \.id) { doc in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(doc.data["title"]?.value as? String ?? doc.id)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text("v\(doc.version) | \(doc.id.prefix(16))...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
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
            .navigationTitle("Query")
        }
    }

    private func parseValue(_ raw: String) -> Any {
        if raw == "true" { return true }
        if raw == "false" { return false }
        if let intVal = Int(raw) { return intVal }
        if let doubleVal = Double(raw) { return doubleVal }
        return raw
    }

    private func mapOperator(_ op: String) -> QueryOperator {
        switch op {
        case "==": return .equal
        case "!=": return .notEqual
        case ">": return .greaterThan
        case ">=": return .greaterThanOrEqual
        case "<": return .lessThan
        case "<=": return .lessThanOrEqual
        default: return .equal
        }
    }

    private func runQuery() {
        isLoading = true
        let limit = Int(limitCount) ?? 10
        Task {
            do {
                let docs = try await collection
                    .where(field, mapOperator(selectedOp), parseValue(value))
                    .limit(limit)
                    .get()
                await MainActor.run {
                    results = docs
                    resultText = "Found \(docs.count) documents"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    resultText = "Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func loadAll() {
        isLoading = true
        Task {
            do {
                let docs = try await collection.getAll()
                await MainActor.run {
                    results = docs.filter { !$0.id.hasPrefix("local_") }
                    resultText = "Found \(results.count) documents"
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    resultText = "Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}
