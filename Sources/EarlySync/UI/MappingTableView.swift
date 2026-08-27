import SwiftUI

// MARK: - MappingTableView

/// Editable table of `ActivityMapping` rows — add/remove mappings, edit their
/// keywords, Luxafor color, Focus profile, and whether Focus is engaged.
/// Changes are held in `appState.mappingConfig` until `Save` persists them.
struct MappingTableView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach($appState.mappingConfig.mappings) { $mapping in
                    MappingRow(mapping: $mapping)
                }
                .onDelete { offsets in
                    appState.mappingConfig.mappings.remove(atOffsets: offsets)
                }
            }
            .frame(minHeight: 240)

            HStack {
                Button {
                    appState.mappingConfig.mappings.append(
                        ActivityMapping(
                            activityNameContains: [],
                            luxaforColor: .white,
                            focusProfileName: nil,
                            enableFocus: false,
                            label: "New Mapping"
                        )
                    )
                } label: {
                    Label("Add Mapping", systemImage: "plus")
                }

                Spacer()

                Button("Save") {
                    appState.saveMapping()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}

// MARK: - MappingRow

private struct MappingRow: View {
    @Binding var mapping: ActivityMapping

    private var keywordsText: Binding<String> {
        Binding(
            get: { mapping.activityNameContains.joined(separator: ", ") },
            set: { newValue in
                mapping.activityNameContains = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Label", text: $mapping.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)

                Picker("", selection: $mapping.luxaforColor) {
                    ForEach(LuxaforColor.allCases, id: \.self) { color in
                        Text("\(color.emoji) \(color.displayName)").tag(color)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                Toggle("Focus", isOn: $mapping.enableFocus)
                    .toggleStyle(.checkbox)
            }

            TextField("Activity keywords (comma separated)", text: keywordsText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            if mapping.enableFocus {
                TextField(
                    "Focus profile name (blank = default)",
                    text: Binding(
                        get: { mapping.focusProfileName ?? "" },
                        set: { mapping.focusProfileName = $0.isEmpty ? nil : $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
