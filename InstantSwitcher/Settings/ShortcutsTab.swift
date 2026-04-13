import KeyboardShortcuts
import SwiftUI

struct ShortcutsTab: View {
    @EnvironmentObject var state: AppState
    @State private var newSpaceIndex: Int = 1
    @State private var newSpaceLabel: String = ""
    @State private var showAddSpaceSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts").font(.headline)
                Spacer()
                Menu {
                    Button("Add app shortcut…") { addApp() }
                    Button("Add space shortcut…") { showAddSpaceSheet = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .frame(width: 90)
            }

            if state.config.bindings.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showAddSpaceSheet) { addSpaceSheet }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No shortcuts yet").font(.headline)
            Text("Add an app shortcut to instantly focus an app on its space, or a space shortcut to jump to a specific space.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(state.config.bindings, id: \.id) { binding in
                row(for: binding)
            }
            .onMove { src, dst in state.moveBinding(fromOffsets: src, toOffset: dst) }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func row(for binding: InstantSwitcher.Binding) -> some View {
        HStack(spacing: 12) {
            switch binding {
            case .app(let b):
                Image(nsImage: icon(for: b)).resizable().frame(width: 22, height: 22)
                VStack(alignment: .leading) {
                    Text(b.displayName).font(.body)
                    Text(b.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                }
            case .space(let b):
                Image(systemName: "square.grid.3x3").frame(width: 22, height: 22)
                VStack(alignment: .leading) {
                    Text(b.label.isEmpty ? "Space \(b.spaceIndex)" : b.label).font(.body)
                    Text("Space \(b.spaceIndex)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            KeyboardShortcuts.Recorder(for: .binding(binding.id))
            Button(role: .destructive) {
                state.deleteBinding(id: binding.id)
            } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func icon(for binding: AppBinding) -> NSImage {
        if let path = binding.iconPath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func addApp() {
        guard let info = AppPicker.pick() else { return }
        state.addAppBinding(bundleID: info.bundleID, displayName: info.displayName, iconPath: info.iconPath)
    }

    private var addSpaceSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add space shortcut").font(.headline)
            HStack {
                Text("Space index")
                Stepper(value: $newSpaceIndex, in: 1...20) { Text("\(newSpaceIndex)") }
            }
            HStack {
                Text("Label")
                TextField("optional", text: $newSpaceLabel)
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddSpaceSheet = false; resetSheet() }
                Button("Add") {
                    state.addSpaceBinding(spaceIndex: newSpaceIndex, label: newSpaceLabel)
                    showAddSpaceSheet = false
                    resetSheet()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func resetSheet() { newSpaceIndex = 1; newSpaceLabel = "" }
}
