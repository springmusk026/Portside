import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: PortStore
    @AppStorage("countInMenuBar") private var countInMenuBar = true
    @AppStorage("notifyChanges") private var notifyChanges = false
    @AppStorage("groupByProject") private var groupByProject = false
    @AppStorage("autoStopHours") private var autoStopHours = 0
    @AppStorage("shortcut") private var shortcut = Shortcut.off.rawValue
    @AppStorage("editor") private var editor = ""
    @AppStorage("terminal") private var terminal = ""
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
                Picker("Open the panel with", selection: $shortcut) {
                    ForEach(Shortcut.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .onChange(of: shortcut) { _, value in Hotkey.apply(Shortcut(rawValue: value) ?? .off) }
            }

            Section {
                Picker("Group servers by", selection: $groupByProject) {
                    Text("Kind").tag(false)
                    Text("Project").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Open projects in", selection: $editor) {
                    let installed = Launcher.editors.filter(\.installed)
                    if installed.isEmpty { Text("No editor found").tag("") }
                    ForEach(installed) { Text($0.name).tag($0.bundleID) }
                }
                .disabled(Launcher.editors.allSatisfy { !$0.installed })
                .onAppear { if editor.isEmpty, let first = Launcher.editor { editor = first.bundleID } }
                Picker("Terminal", selection: $terminal) {
                    ForEach(Launcher.terminals.filter(\.installed)) { Text($0.name).tag($0.bundleID) }
                }
                .onAppear { if terminal.isEmpty { terminal = Launcher.terminal.bundleID } }
            }

            Section {
                Picker(selection: $autoStopHours) {
                    Text("Never").tag(0)
                    Text("After 8 hours").tag(8)
                    Text("After a day").tag(24)
                    Text("After 3 days").tag(72)
                } label: {
                    Text("Stop forgotten dev servers")
                    Text("Sends SIGTERM to dev servers running longer than this. Pinned servers, services and containers are never stopped.")
                }
            }

            if !store.hidden.isEmpty {
                Section("Hidden") {
                    ForEach(store.hidden.sorted(), id: \.self) { key in
                        HStack {
                            Text(key.split(separator: "|").last.map(String.init) ?? key)
                            Text(key.split(separator: "|").first.map { Kind(rawValue: String($0))?.section ?? "" } ?? "")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Unhide") { store.unhide(key) }
                        }
                    }
                }
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
