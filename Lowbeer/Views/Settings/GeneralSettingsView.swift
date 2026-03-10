import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings = LowbeerSettings.shared

    private var actionBinding: Binding<String> {
        Binding(
            get: {
                switch settings.defaultAction {
                case .stop: return "stop"
                case .throttleTo: return "throttle"
                case .notifyOnly: return "notify"
                }
            },
            set: { newValue in
                switch newValue {
                case "stop": settings.defaultAction = .stop
                case "throttle": settings.defaultAction = .throttleTo(0.25)
                case "notify": settings.defaultAction = .notifyOnly
                default: break
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("CPU Threshold") {
                HStack {
                    Slider(value: $settings.globalCPUThreshold, in: 10...200, step: 5) {
                        Text("Threshold")
                    }
                    Text(String(format: "%.0f%%", settings.globalCPUThreshold))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 50)
                }

                Stepper(
                    "Sustained for \(settings.sustainedSeconds)s",
                    value: $settings.sustainedSeconds,
                    in: 5...300,
                    step: 5
                )
            }

            Section("Throttle Mode") {
                Picker("When threshold exceeded:", selection: $settings.throttleMode) {
                    Text("Throttle automatically").tag(ThrottleMode.automatic)
                    Text("Ask me first (notification)").tag(ThrottleMode.askFirst)
                }
                .pickerStyle(.radioGroup)

                if settings.throttleMode == .automatic {
                    Picker("Action:", selection: actionBinding) {
                        Text("Stop process (SIGSTOP)").tag("stop")
                        Text("Throttle to 25% CPU").tag("throttle")
                        Text("Notify only").tag("notify")
                    }
                    .pickerStyle(.radioGroup)
                    .padding(.leading, 8)
                }
            }

            Section("Polling") {
                Picker("Check every:", selection: $settings.pollInterval) {
                    Text("1 second").tag(1.0 as TimeInterval)
                    Text("3 seconds").tag(3.0 as TimeInterval)
                    Text("5 seconds").tag(5.0 as TimeInterval)
                    Text("10 seconds").tag(10.0 as TimeInterval)
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                Toggle("Send notifications", isOn: $settings.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error)")
            settings.launchAtLogin = !enabled  // Revert on failure
        }
    }
}
