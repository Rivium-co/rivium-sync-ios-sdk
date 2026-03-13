import SwiftUI
import RiviumSync
import Combine

struct ContentView: View {
    @StateObject private var connectionManager = ConnectionManager()

    var body: some View {
        TabView {
            CrudView()
                .tabItem {
                    Label("CRUD", systemImage: "doc.text")
                }

            QueryView()
                .tabItem {
                    Label("Query", systemImage: "magnifyingglass")
                }

            BatchView()
                .tabItem {
                    Label("Batch", systemImage: "square.stack.3d.up")
                }

            RealtimeView()
                .tabItem {
                    Label("Realtime", systemImage: "bolt.fill")
                }

            OfflineView(connectionManager: connectionManager)
                .tabItem {
                    Label("Offline", systemImage: "icloud.and.arrow.up")
                }
        }
        .accentColor(.green)
        .safeAreaInset(edge: .top) {
            ConnectionBar(connectionManager: connectionManager)
        }
        .environmentObject(connectionManager)
    }
}

// MARK: - Connection Manager

class ConnectionManager: NSObject, ObservableObject, RiviumSyncDelegate {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var syncState: SyncState = .idle
    @Published var pendingCount: Int = 0

    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        RiviumSync.shared.delegate = self
        setupObservers()
        autoConnect()
    }

    private func setupObservers() {
        RiviumSync.shared.syncStatePublisher?.receive(on: DispatchQueue.main).sink { [weak self] state in
            self?.syncState = state
        }.store(in: &cancellables)

        RiviumSync.shared.pendingCountPublisher?.receive(on: DispatchQueue.main).sink { [weak self] count in
            self?.pendingCount = count
        }.store(in: &cancellables)
    }

    func autoConnect() {
        guard !isConnected && !isConnecting else { return }
        isConnecting = true
        Task {
            do {
                try await RiviumSync.shared.connect()
                await MainActor.run {
                    self.isConnected = true
                    self.isConnecting = false
                }
            } catch {
                await MainActor.run {
                    self.isConnected = false
                    self.isConnecting = false
                }
            }
        }
    }

    func toggleConnection() {
        guard !isConnecting else { return }
        isConnecting = true
        if isConnected {
            RiviumSync.shared.disconnect()
            isConnected = false
            isConnecting = false
        } else {
            Task {
                do {
                    try await RiviumSync.shared.connect()
                    await MainActor.run {
                        self.isConnected = true
                        self.isConnecting = false
                    }
                } catch {
                    await MainActor.run {
                        self.isConnected = false
                        self.isConnecting = false
                    }
                }
            }
        }
    }

    // MARK: - RiviumSyncDelegate

    func riviumSyncDidConnect(_ riviumSync: RiviumSync) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.isConnecting = false
        }
    }

    func riviumSync(_ riviumSync: RiviumSync, didDisconnectWithError error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
        }
    }

    func riviumSync(_ riviumSync: RiviumSync, didFailToConnectWithError error: Error) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.isConnecting = false
        }
    }
}

// MARK: - Connection Bar

struct ConnectionBar: View {
    @ObservedObject var connectionManager: ConnectionManager

    var dotColor: Color {
        if connectionManager.isConnecting { return .orange }
        if connectionManager.isConnected { return .green }
        return .red
    }

    var statusText: String {
        if connectionManager.isConnecting { return "Connecting..." }
        if connectionManager.isConnected { return "Connected" }
        return "Disconnected"
    }

    var body: some View {
        HStack {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.caption)
                .foregroundColor(.white)

            Spacer()

            Button {
                connectionManager.toggleConnection()
            } label: {
                Text(connectionManager.isConnected ? "Disconnect" : "Connect")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white, lineWidth: 1)
                    )
            }
            .disabled(connectionManager.isConnecting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.02, green: 0.47, blue: 0.34))
    }
}
