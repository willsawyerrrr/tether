import SwiftUI
import TetherIPC

extension SpawnMode {
    var title: String {
        switch self {
        case .sameDir: "Same Directory"
        case .worktree: "Worktree"
        }
    }
}

/// The app's settings: the spawn mode directories follow unless they override it.
struct SettingsView: View {
    @AppStorage(SpawnMode.defaultKey) private var defaultSpawnMode = SpawnMode.sameDir

    var body: some View {
        Form {
            Picker("Default spawn mode", selection: $defaultSpawnMode) {
                ForEach(SpawnMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Applies to directories without their own setting, the next time their server starts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420)
    }
}
