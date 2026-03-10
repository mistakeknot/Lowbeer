import SwiftUI

struct AllowlistView: View {
    @Bindable var settings = LowbeerSettings.shared
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Built-in protected list
            GroupBox("Built-in (always protected)") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(SafetyList.protectedNames.sorted()), id: \.self) { name in
                            HStack {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }

                        Divider().padding(.vertical, 4)

                        ForEach(SafetyList.protectedPathPrefixes, id: \.self) { prefix in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(prefix + "*")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 150)
            }

            Divider().padding(.vertical, 8)

            // User-added allowlist
            GroupBox("Custom (never throttle)") {
                if settings.userAllowlist.isEmpty {
                    ContentUnavailableView(
                        "No custom entries",
                        systemImage: "shield",
                        description: Text("Add processes you never want throttled.")
                    )
                    .frame(height: 80)
                } else {
                    List {
                        ForEach(Array(settings.userAllowlist.enumerated()), id: \.element.displayName) { index, identity in
                            HStack {
                                Text(identity.displayName)
                                if let bid = identity.bundleIdentifier {
                                    Text(bid)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    settings.userAllowlist.remove(at: index)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            HStack {
                Button(action: { showingAddSheet = true }) {
                    Label("Add", systemImage: "plus")
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            AddAllowlistSheet(settings: settings)
        }
    }
}

struct AddAllowlistSheet: View {
    let settings: LowbeerSettings
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var bundleID = ""
    @State private var execPath = ""

    var body: some View {
        Form {
            TextField("Process name", text: $displayName)
            TextField("Bundle ID (optional)", text: $bundleID)
            TextField("Executable path (optional)", text: $execPath)

            Picker("Pick from running:", selection: Binding(
                get: { "" },
                set: { val in
                    if !val.isEmpty {
                        let parts = val.split(separator: "|", maxSplits: 2)
                        if parts.count >= 1 { displayName = String(parts[0]) }
                        if parts.count >= 2 { bundleID = String(parts[1]) }
                    }
                }
            )) {
                Text("Select...").tag("")
                ForEach(runningApps, id: \.self) { app in
                    Text(app.split(separator: "|").first.map(String.init) ?? app)
                        .tag(app)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 250)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let identity = AppIdentity(
                        bundleIdentifier: bundleID.isEmpty ? nil : bundleID,
                        executablePath: execPath.isEmpty ? nil : execPath,
                        displayName: displayName
                    )
                    settings.userAllowlist.append(identity)
                    dismiss()
                }
                .disabled(displayName.isEmpty)
            }
        }
    }

    private var runningApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> String? in
                guard let name = app.localizedName else { return nil }
                return "\(name)|\(app.bundleIdentifier ?? "")"
            }
            .sorted()
    }
}
