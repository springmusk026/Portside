// Keeps the server list fresh (a scan every 3 seconds costs about a millisecond),
// stops servers, and sends start/stop notifications.

import AppKit
import SwiftUI
import UserNotifications

/// Scans once: listening processes, plus container names when a container runtime is listening.
func scanServers() -> [Server] {
    let procs = Scanner.listeningProcesses()
    let needsDocker = procs.contains { Classifier.classify($0).0 == .container }
    return Classifier.servers(from: procs, containers: needsDocker ? Docker.containers() : [])
}

enum StopState: Equatable {
    case stopping(since: Date)
    case stuck   // still listening a few seconds after SIGTERM
}

enum PortLookup: Equatable {
    case held([Server])
    case free
    case hidden   // in use, but by a process Portside can't see (root or another user)
}

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published private(set) var loaded = false
    @Published private(set) var stopping: [String: StopState] = [:]
    @Published private(set) var now = Date()
    @Published private(set) var lanAddress: String?
    /// Servers moved down with the apps, and ones kept at the top and never stopped
    /// automatically, by `Server.nameKey`.
    @Published private(set) var hidden: Set<String>
    @Published private(set) var pinned: Set<String>

    @AppStorage("notifyChanges") var notifyChanges = false
    /// Stop dev servers that have run longer than this; 0 is never.
    @AppStorage("autoStopHours") var autoStopHours = 0

    private var loop: Task<Void, Never>?
    private var tracker = ChangeTracker()
    private var demo = false

    /// With `servers`, a fixed demo store for snapshots: no scanning.
    init(servers: [Server]? = nil, stopping: [String: StopState] = [:], pinned: Set<String> = []) {
        let defaults = UserDefaults.standard
        hidden = servers == nil ? Set(defaults.stringArray(forKey: "hidden") ?? []) : []
        self.pinned = servers == nil ? Set(defaults.stringArray(forKey: "pinned") ?? []) : pinned
        if let servers {
            self.servers = servers
            self.stopping = stopping
            demo = true
            loaded = true
            lanAddress = "192.168.1.24"
            return
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// Dev servers, services and containers, pinned ones first in each kind.
    var visible: [Server] {
        let shown = servers.filter { $0.kind != .app && !hidden.contains($0.nameKey) }
        return shown.filter { pinned.contains($0.nameKey) } + shown.filter { !pinned.contains($0.nameKey) }
    }

    /// Apps, system processes and servers you've hidden.
    var apps: [Server] { servers.filter { $0.kind == .app || hidden.contains($0.nameKey) } }

    func isHidden(_ server: Server) -> Bool { hidden.contains(server.nameKey) }
    func isPinned(_ server: Server) -> Bool { pinned.contains(server.nameKey) }

    func setHidden(_ server: Server, _ on: Bool) {
        withAnimation(Motion.spring) { if on { hidden.insert(server.nameKey) } else { hidden.remove(server.nameKey) } }
        if !demo { UserDefaults.standard.set(hidden.sorted(), forKey: "hidden") }
    }

    func unhide(_ key: String) {
        withAnimation(Motion.spring) { _ = hidden.remove(key) }
        if !demo { UserDefaults.standard.set(hidden.sorted(), forKey: "hidden") }
    }

    func setPinned(_ server: Server, _ on: Bool) {
        withAnimation(Motion.spring) { if on { pinned.insert(server.nameKey) } else { pinned.remove(server.nameKey) } }
        if !demo { UserDefaults.standard.set(pinned.sorted(), forKey: "pinned") }
    }

    /// The other servers of the project this one belongs to, including it.
    func project(of server: Server) -> [Server] {
        guard let group = server.group else { return [server] }
        return visible.filter { $0.group == group }
    }

    /// The panel's sections: by kind, or by project with the rest under "Other".
    func sections(_ servers: [Server], byProject: Bool) -> [ServerGroup] {
        guard byProject else {
            return [Kind.dev, .service, .container].compactMap { kind in
                let rows = servers.filter { $0.kind == kind }
                return rows.isEmpty ? nil : ServerGroup(id: kind.rawValue, title: kind.section, servers: rows)
            }
        }
        var order: [String] = []
        var groups: [String: [Server]] = [:]
        for s in servers {
            guard let g = s.group else { continue }
            if groups[g] == nil { order.append(g) }
            groups[g, default: []].append(s)
        }
        // Projects with a dev server first, then by name
        order.sort {
            let a = groups[$0]!.contains { $0.kind == .dev }, b = groups[$1]!.contains { $0.kind == .dev }
            return a != b ? a : ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending
        }
        var result = order.map { g in
            ServerGroup(id: g, title: (g as NSString).lastPathComponent, servers: groups[g]!, project: g)
        }
        let rest = servers.filter { $0.group == nil }
        if !rest.isEmpty { result.append(ServerGroup(id: "other", title: "Other", servers: rest)) }
        return result
    }

    func refresh() async {
        let fresh = await Task.detached(priority: .utility) { scanServers() }.value
        let lan = await Task.detached(priority: .utility) { Scanner.lanAddress() }.value
        now = Date()
        lanAddress = lan
        let ids = Set(fresh.map(\.id))
        // A server that's gone has stopped; one that's still there after 4 seconds is stuck
        for (id, state) in stopping {
            if !ids.contains(id) { stopping[id] = nil }
            else if case .stopping(let since) = state, now.timeIntervalSince(since) > 4 { stopping[id] = .stuck }
        }
        let events = tracker.update(fresh.filter { $0.kind != .app && !hidden.contains($0.nameKey) }, initial: !loaded)
        if notifyChanges { events.forEach(Notifier.send) }
        if fresh != servers { withAnimation(Motion.spring) { servers = fresh } }
        loaded = true
        autoStop()
    }

    /// Stops dev servers left running longer than the limit in Settings, except pinned ones.
    private func autoStop() {
        guard autoStopHours > 0, !demo else { return }
        let limit = TimeInterval(autoStopHours) * 3600
        for s in visible where s.kind == .dev && !isPinned(s) && stopping[s.id] == nil {
            guard let started = s.started, now.timeIntervalSince(started) > limit else { continue }
            stop(s)
            if notifyChanges { Notifier.send(.autoStopped(s, after: now.timeIntervalSince(started))) }
        }
    }

    // MARK: Actions

    func stop(_ server: Server, force: Bool = false) {
        stop([server], force: force)
    }

    /// Stops servers together: a runner they share (`concurrently`, `turbo`) goes too,
    /// which it wouldn't when stopping just one of them.
    func stop(_ servers: [Server], force: Bool = false) {
        let pids = Set(servers.compactMap(\.pid))
        for server in servers where server.kind.stoppable || force {
            tracker.expectStop(server.key)
            stopping[server.id] = .stopping(since: Date())
            if let name = server.container {
                Task.detached { Docker.stop(name, force: force) }
            } else if let pid = server.pid {
                guard !demo else { continue }
                Killer.stop(pid, force: force, together: pids)
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            await refresh()
        }
    }

    func stopAll() {
        stop(visible.filter { $0.kind == .dev })
    }

    func lookup(_ port: UInt16) -> PortLookup {
        let held = servers.filter { $0.portNumbers.contains(port) }
        if !held.isEmpty { return .held(held) }
        if demo { return port == 631 ? .hidden : .free }   // CUPS, owned by root
        return Scanner.portInUse(port) ? .hidden : .free
    }

    func open(_ server: Server) {
        if let url = URL(string: server.url) { NSWorkspace.shared.open(url) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func reveal(_ server: Server) {
        if let dir = server.directory {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir)
        }
    }

    func openInTerminal(_ server: Server) {
        if let dir = server.directory { Launcher.open(dir, with: Launcher.terminal) }
    }

    func openInEditor(_ server: Server) {
        if let dir = server.directory, let editor = Launcher.editor { Launcher.open(dir, with: editor) }
    }
}

/// A section of the panel: one kind of server, or one project.
struct ServerGroup: Identifiable {
    let id: String
    let title: String
    let servers: [Server]
    /// The project folder, when the section is a project.
    var project: String? = nil
}

// MARK: - Notifications

enum ChangeEvent {
    case started(Server)
    case stopped(Server)
    case autoStopped(Server, after: TimeInterval)
}

/// Turns successive scans into start/stop events. A server must be seen in two scans
/// in a row to count as started, and missing from two to count as stopped, so quick
/// restarts (file watchers, hot reload) don't notify.
struct ChangeTracker {
    private var known: [String: Server] = [:]
    private var pendingStart: Set<String> = []
    private var pendingStop: Set<String> = []
    private var expected: Set<String> = []

    mutating func expectStop(_ key: String) { expected.insert(key) }

    mutating func update(_ servers: [Server], initial: Bool) -> [ChangeEvent] {
        let current = Dictionary(servers.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        if initial {
            known = current
            return []
        }
        var events: [ChangeEvent] = []
        for (key, server) in current where known[key] == nil {
            if pendingStart.remove(key) != nil {
                known[key] = server
                events.append(.started(server))
            } else {
                pendingStart.insert(key)
            }
        }
        pendingStart.formIntersection(current.keys)
        for (key, server) in known {
            if current[key] != nil { pendingStop.remove(key); known[key] = current[key]; continue }
            if pendingStop.remove(key) != nil || expected.contains(key) {
                known[key] = nil
                // Stopped from Portside: you already know
                if expected.remove(key) == nil { events.append(.stopped(server)) }
            } else {
                pendingStop.insert(key)
            }
        }
        return events
    }
}

enum Notifier {
    /// Notifications need an app bundle; a bare binary (the CLI, a dev build) has none.
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(_ event: ChangeEvent) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        switch event {
        case .started(let s):
            content.title = "\(s.title) started"
            content.body = "\(s.detail) on :\(s.primaryPort)" + (s.exposed ? ", open to your network" : "")
        case .stopped(let s):
            content.title = "\(s.title) stopped"
            content.body = "\(s.detail) is no longer listening on :\(s.primaryPort)"
        case .autoStopped(let s, let after):
            content.title = "Stopped \(s.title)"
            content.body = "\(s.detail) on :\(s.primaryPort) had been running for \(fmtUptime(after))"
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
