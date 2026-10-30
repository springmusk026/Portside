// The command line. Run the app binary with arguments, or link it as `portside`:
//   portside                 list servers
//   portside 3000            who holds port 3000
//   portside kill 3000 8000  stop them (--force to SIGKILL)
//   portside open 3000       open it in the browser
//   portside wait 3000       wait until something listens on it (--free: until nothing does)
//   portside --json          machine-readable list
//   portside --all           include apps and system processes

import AppKit

enum CLI {
    /// Whether this launch is a command-line run rather than the menu bar app.
    static func wants(_ args: [String]) -> Bool {
        let invokedAs = (args.first.map { ($0 as NSString).lastPathComponent } ?? "")
        let flags = Array(args.dropFirst()).filter { !$0.hasPrefix("-psn") && !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") }
        return invokedAs == "portside" || flags.contains { ["--json", "--list", "--all", "--help", "-h", "kill", "open", "wait", "--version"].contains($0) || UInt16($0) != nil }
    }

    static func run(_ argv: [String]) -> Int32 {
        let args = Array(argv.dropFirst())
        let all = args.contains("--all")
        let color = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
        let style = Style(enabled: color)

        if args.contains("--help") || args.contains("-h") { print(help); return 0 }
        if args.contains("--version") { print("portside \(version)"); return 0 }

        let servers = scanServers().filter { all || $0.kind != .app }

        if args.contains("--json") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write((try? encoder.encode(servers)) ?? Data("[]".utf8))
            print()
            return 0
        }

        if let i = args.firstIndex(of: "kill") {
            let ports = args[(i + 1)...].compactMap { UInt16($0) }
            guard !ports.isEmpty else { printError("usage: portside kill <port>... [--force]"); return 2 }
            return kill(ports, force: args.contains("--force"), style: style)
        }

        if let i = args.firstIndex(of: "open") {
            guard i + 1 < args.count, let port = UInt16(args[i + 1]) else { printError("usage: portside open <port>"); return 2 }
            guard let server = scanServers().first(where: { $0.portNumbers.contains(port) }) else {
                printError("Nothing Portside can see is listening on :\(port)."); return 1
            }
            let url = server.address(host: "localhost").replacingOccurrences(of: ":\(server.primaryPort)", with: ":\(port)")
            guard url.hasPrefix("http"), let target = URL(string: url) else {
                printError("\(server.title) isn't a web server; its address is \(url)"); return 1
            }
            NSWorkspace.shared.open(target)
            print("Opened \(url)")
            return 0
        }

        if let i = args.firstIndex(of: "wait") {
            guard i + 1 < args.count, let port = UInt16(args[i + 1]) else {
                printError("usage: portside wait <port> [--free] [--timeout <seconds>]"); return 2
            }
            let timeout = args.firstIndex(of: "--timeout").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 60
            return wait(port, untilFree: args.contains("--free"), timeout: timeout)
        }

        if let port = args.compactMap({ UInt16($0) }).first {
            let holders = scanServers().filter { $0.portNumbers.contains(port) }
            if holders.isEmpty {
                if Scanner.portInUse(port) {
                    print("Port \(port) is in use by a process Portside can't see (another user or root).")
                    return 1
                }
                print("Port \(port) is \(style.green("free")).")
                return 0
            }
            print(table(holders, style: style))
            return 1   // like `lsof`, non-zero when the port is taken, for scripts
        }

        if servers.isEmpty {
            print(all ? "Nothing is listening." : "No dev servers running. (portside --all shows apps too)")
            return 0
        }
        print(table(servers, style: style))
        return 0
    }

    /// Stops whatever holds each port. Servers sharing a runner (`concurrently`) are stopped together.
    private static func kill(_ ports: [UInt16], force: Bool, style: Style) -> Int32 {
        let all = scanServers()
        let pids = Set(all.filter { !Set($0.portNumbers).isDisjoint(with: ports) }.compactMap(\.pid))
        var ok = true
        var done = Set<String>()
        for port in ports {
            let holders = all.filter { $0.portNumbers.contains(port) }
            guard !holders.isEmpty else {
                if Scanner.portInUse(port) {
                    printError("Port \(port) is held by a process Portside can't see (another user or root). Try: sudo lsof -i :\(port)")
                    ok = false
                } else {
                    print("Port \(port) is already free.")
                }
                continue
            }
            for s in holders where !done.contains(s.id) {
                done.insert(s.id)
                guard s.kind.stoppable || force else {
                    printError("\(s.title) is an app; quit it normally, or pass --force."); ok = false; continue
                }
                if Killer.stopAndWait(s, force: force, together: pids) {
                    print("Stopped \(style.bold(s.title)) (\(s.detail)) on :\(port)")
                } else {
                    printError("\(s.title) is still running. Try: portside kill \(port) --force"); ok = false
                }
            }
        }
        return ok ? 0 : 1
    }

    /// Waits for a port to be taken (or freed). 0 when it happens, 1 on timeout.
    private static func wait(_ port: UInt16, untilFree: Bool, timeout: TimeInterval) -> Int32 {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let taken = Scanner.portInUse(port) || scanServers().contains { $0.portNumbers.contains(port) }
            if taken != untilFree { return 0 }
            if Date() >= deadline {
                printError("Timed out after \(Int(timeout)) s: port \(port) is still \(untilFree ? "taken" : "free").")
                return 1
            }
            usleep(250_000)
        }
    }

    static func table(_ servers: [Server], style: Style) -> String {
        let now = Date()
        let rows = servers.map { row($0, now: now) }
        let header = ["PORT", "NAME", "WHAT", "PID", "UP", "REACH", "WHERE"]
        let widths = header.indices.map { i in ([header[i]] + rows.map { $0[i] }).map(\.count).max() ?? 0 }
        func line(_ cells: [String], styled: (Int, String) -> String) -> String {
            cells.enumerated().map { i, c in
                let padded = i == cells.count - 1 ? c : c.padding(toLength: widths[i], withPad: " ", startingAt: 0)
                return styled(i, padded)
            }.joined(separator: "  ")
        }
        var out = [line(header) { _, c in style.dim(c) }]
        for row in rows {
            out.append(line(row) { i, c in
                switch i {
                case 0: return style.green(c)
                case 1: return style.bold(c)
                case 5: return c.hasPrefix("network") ? style.yellow(c) : style.dim(c)
                case 3, 4, 6: return style.dim(c)
                default: return c
                }
            })
        }
        return out.joined(separator: "\n")
    }

    private static func row(_ s: Server, now: Date) -> [String] {
        let ports = s.portNumbers.map(String.init).joined(separator: ",")
        let pid = s.pid.map(String.init) ?? "–"
        var up = "–"
        if let status = s.status { up = dockerUptime(status) } else if let started = s.started { up = fmtUptime(now.timeIntervalSince(started)) }
        var place = ""
        if let dir = s.directory { place = abbreviate(dir) } else if let name = s.container { place = "docker: \(name)" }
        return [ports, s.title, s.detail, pid, up, s.exposed ? "network" : "local", place]
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static let help = """
    portside: see and stop what's listening on your ports

      portside                 list dev servers, services and containers
      portside --all           include apps and system processes
      portside <port>          who holds a port (exits 1 if taken, 0 if free)
      portside kill <port>...  stop whatever holds the ports (--force to SIGKILL)
      portside open <port>     open a web server in your browser
      portside wait <port>     wait until something listens (--free: until nothing does;
                               --timeout <seconds>, default 60; exits 1 on timeout)
      portside --json          the list as JSON, for scripts

    Run without arguments from Finder or Spotlight for the menu bar app.
    """

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    struct Style {
        let enabled: Bool
        private func wrap(_ code: String, _ s: String) -> String { enabled ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }
        func bold(_ s: String) -> String { wrap("1", s) }
        func dim(_ s: String) -> String { wrap("2", s) }
        func green(_ s: String) -> String { wrap("32", s) }
        func yellow(_ s: String) -> String { wrap("33", s) }
    }
}
