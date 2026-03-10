import SwiftUI

struct RulesSettingsView: View {
    @Bindable var settings = LowbeerSettings.shared
    @State private var selection: UUID?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Rules table
            Table(settings.rules, selection: $selection) {
                TableColumn("App") { rule in
                    Text(rule.identity.displayName)
                }
                TableColumn("Threshold") { rule in
                    Text(String(format: "%.0f%%", rule.cpuThreshold))
                }
                .width(70)
                TableColumn("Duration") { rule in
                    Text("\(rule.sustainedSeconds)s")
                }
                .width(60)
                TableColumn("Action") { rule in
                    switch rule.action {
                    case .stop: Text("Stop")
                    case .throttleTo(let v): Text("\(Int(v * 100))%")
                    case .notifyOnly: Text("Notify")
                    }
                }
                .width(60)
                TableColumn("Enabled") { rule in
                    let idx = settings.rules.firstIndex(where: { $0.id == rule.id })
                    if let idx {
                        Toggle("", isOn: $settings.rules[idx].enabled)
                            .labelsHidden()
                    }
                }
                .width(60)
            }

            // Toolbar
            HStack {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                Spacer()
            }
            .padding(8)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddRuleSheet(settings: settings)
        }
    }

    private func removeSelected() {
        guard let sel = selection else { return }
        settings.rules.removeAll { $0.id == sel }
        selection = nil
    }
}

struct AddRuleSheet: View {
    let settings: LowbeerSettings
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var bundleID = ""
    @State private var execPath = ""
    @State private var threshold: Double = 80
    @State private var sustained: Int = 30
    @State private var action: String = "stop"
    @State private var backgroundOnly = true

    var body: some View {
        Form {
            Section("Application") {
                TextField("Name", text: $displayName)
                TextField("Bundle ID (optional)", text: $bundleID)
                TextField("Executable path (optional)", text: $execPath)

                // Quick pick from running apps
                Picker("Pick from running:", selection: Binding(
                    get: { "" },
                    set: { val in
                        if !val.isEmpty {
                            let parts = val.split(separator: "|", maxSplits: 2)
                            if parts.count == 2 {
                                displayName = String(parts[0])
                                bundleID = String(parts[1])
                            }
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

            Section("Threshold") {
                HStack {
                    Slider(value: $threshold, in: 10...200, step: 5)
                    Text(String(format: "%.0f%%", threshold))
                        .frame(width: 50)
                }
                Stepper("Sustained for \(sustained)s", value: $sustained, in: 5...300, step: 5)
            }

            Section("Action") {
                Picker("Action:", selection: $action) {
                    Text("Stop (SIGSTOP)").tag("stop")
                    Text("Throttle to 25%").tag("throttle25")
                    Text("Throttle to 50%").tag("throttle50")
                    Text("Notify only").tag("notify")
                }
                Toggle("Only in background", isOn: $backgroundOnly)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { addRule(); dismiss() }
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

    private func addRule() {
        let identity = AppIdentity(
            bundleIdentifier: bundleID.isEmpty ? nil : bundleID,
            executablePath: execPath.isEmpty ? nil : execPath,
            displayName: displayName
        )

        let throttleAction: ThrottleAction
        switch action {
        case "stop": throttleAction = .stop
        case "throttle25": throttleAction = .throttleTo(0.25)
        case "throttle50": throttleAction = .throttleTo(0.50)
        case "notify": throttleAction = .notifyOnly
        default: throttleAction = .stop
        }

        let rule = ThrottleRule(
            identity: identity,
            cpuThreshold: threshold,
            sustainedSeconds: sustained,
            action: throttleAction,
            throttleInBackground: backgroundOnly
        )
        settings.rules.append(rule)
    }
}
