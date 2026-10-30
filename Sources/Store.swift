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

    @AppStorage("notifyChanges") var notifyChanges = false

    private var loop: Task<Void, Never>?
    private var tracker = ChangeTracker()
    private var demo = false

    /// With `servers`, a fixed demo store for snapshots: no scanning.
    init(servers: [Server]? = nil, stopping: [String: StopState] = [:]) {
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

    var visible: [Server] { servers.filter { $0.kind != .app } }
    var apps: [Server] { servers.filter { $0.kind == .app } }

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
        let events = tracker.update(fresh.filter { $0.kind != .app }, initial: !loaded)
        if notifyChanges { events.forEach(Notifier.send) }
        if fresh != servers { withAnimation(Motion.spring) { servers = fresh } }
        loaded = true
    }

    // MARK: Actions

    func stop(_ server: Server, force: Bool = false) {
        tracker.expectStop(server.key)
        stopping[server.id] = .stopping(since: Date())
        if let name = server.container {
            Task.detached { Docker.stop(name, force: force) }
        } else if let pid = server.pid {
            Killer.stop(pid, force: force)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            await refresh()
        }
    }

    func stopAll() {
        visible.filter { $0.kind == .dev }.forEach { stop($0) }
    }

    func lookup(_ port: UInt16) -> PortLookup {
        let held = servers.filter { $0.portNumbers.contains(port) }
        if !held.isEmpty { return .held(held) }
        if demo { return port < 1024 ? .hidden : .free }
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
        guard let dir = server.directory else { return }
        let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        if let terminal {
            NSWorkspace.shared.open([URL(fileURLWithPath: dir)], withApplicationAt: terminal,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

// MARK: - Stopping processes

enum Killer {
    /// Programs that run a dev server on someone's behalf (`npm run dev` → node → next).
    /// Stopping only the listening child often leaves the parent to restart it.
    static let runners: Set<String> = ["node", "npm", "npx", "pnpm", "yarn", "bun", "bunx", "deno", "uv", "poetry",
                                       "pipenv", "bundle", "rake", "cargo", "go", "air", "nodemon", "watchexec",
                                       "turbo", "nx", "concurrently", "foreman", "overmind", "honcho", "mix", "gradle",
                                       "java", "php", "dotnet"]

    /// The listening process and the runners above it in the same folder, outermost first.
    static func chain(_ pid: Int32) -> [Int32] {
        var result = [pid]
        let cwd = Scanner.workingDirectory(pid)
        var current = pid
        for _ in 0..<4 {
            guard let info = Scanner.bsdInfo(current) else { break }
            let parent = Int32(info.pbi_ppid)
            guard parent > 1, let parentInfo = Scanner.bsdInfo(parent) else { break }
            let name = withUnsafeBytes(of: parentInfo.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let isRunner = runners.contains(name) || name.hasPrefix("python") || name.hasPrefix("ruby")
            guard isRunner, Scanner.workingDirectory(parent) == cwd else { break }
            result.insert(parent, at: 0)
            current = parent
        }
        return result
    }

    static func stop(_ pid: Int32, force: Bool) {
        for p in chain(pid) { kill(p, force ? SIGKILL : SIGTERM) }
    }

    /// For the command line: stops the server and waits up to `timeout` for it to exit.
    static func stopAndWait(_ server: Server, force: Bool, timeout: TimeInterval = 4) -> Bool {
        if let name = server.container {
            Docker.stop(name, force: force)
            return !scanServers().contains { $0.container == name }
        }
        guard let pid = server.pid else { return false }
        stop(pid, force: force)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !Scanner.isAlive(pid) { return true }
            usleep(100_000)
        }
        return !Scanner.isAlive(pid)
    }
}

// MARK: - Notifications

enum ChangeEvent {
    case started(Server)
    case stopped(Server)
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
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
