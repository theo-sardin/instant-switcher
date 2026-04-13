import SwiftUI

struct AboutTab: View {
    @EnvironmentObject var state: AppState
    @State private var initialized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: "square.grid.3x3.square")
                    .font(.system(size: 48))
                VStack(alignment: .leading) {
                    Text("InstantSwitcher").font(.title2).bold()
                    Text("v\(version)").foregroundStyle(.secondary)
                }
            }

            coreStatusRow

            VStack(alignment: .leading, spacing: 4) {
                Text("Credits").font(.headline)
                Text("Powered by ") + Text("[InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)")
                    + Text(" (MIT) by jurplel.")
                Button("View upstream license") { openLicense() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
        .onAppear { initialized = state.core.isInitialized }
    }

    private var coreStatusRow: some View {
        HStack(spacing: 8) {
            if initialized {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("ISS core initialized").font(.caption)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("ISS core not initialized — grant Accessibility").font(.caption)
                Button("Retry") {
                    initialized = state.core.ensureInitialized()
                }.controlSize(.small)
            }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private func openLicense() {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else { return }
        NSWorkspace.shared.open(url)
    }
}
