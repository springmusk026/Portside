import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: PortStore
    @AppStorage("countInMenuBar") private var countInMenuBar = true
    @AppStorage("notifyChanges") private var notifyChanges = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var notificationsDenied = false
    @State private var copied = false

    private var linkCommand: String {
        let binary = Bundle.main.executableURL?.path ?? "/Applications/Portside.app/Contents/MacOS/Portside"
        let bin = FileManager.default.isWritableFile(atPath: "/opt/homebrew/bin") ? "/opt/homebrew/bin" : "/usr/local/bin"
        return "ln -sf '\(binary)' \(bin)/portside"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show the number of running servers in the menu bar", isOn: $countInMenuBar)
            }

            Section {
                Toggle(isOn: $notifyChanges) {
                    Text("Notify when a server starts or stops")
                    Text(notificationsDenied
                         ? "Notifications are turned off for Portside in System Settings › Notifications."
                         : "Not for servers you stop from Portside, and not for quick restarts during hot reload.")
                }
                .onChange(of: notifyChanges) { _, on in if on { Notifier.requestPermission(); checkNotifications() } }
            }

            Section("Command line") {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Add `portside` to your PATH to list, look up and stop servers from Terminal:")
                    HStack {
                        Text(linkCommand)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button(copied ? "Copied" : "Copy") {
                            store.copy(linkCommand)
                            copied = true
                            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                        }
                    }
                    Text("Then try `portside`, `portside 3000` or `portside kill 3000`.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Version", value: CLI.version)
                LabeledContent("Source") {
                    Link("github.com/springmusk026/Portside", destination: URL(string: "https://github.com/springmusk026/Portside")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: checkNotifications)
    }

    private func checkNotifications() {
        guard Notifier.available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in notificationsDenied = denied }
        }
    }
}
