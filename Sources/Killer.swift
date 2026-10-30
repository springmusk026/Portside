// Stops a server: the listening process, plus the runner above it (`npm run dev` → node → next)
// that would otherwise restart it, but never a runner that other servers still depend on.

import Darwin
import Foundation

enum Killer {
    /// Programs that run a dev server on someone's behalf (`npm run dev` → node → next).
    /// Stopping only the listening child often leaves the parent to restart it.
    static let runners: Set<String> = ["node", "npm", "npx", "pnpm", "yarn", "bun", "bunx", "deno", "uv", "poetry",
                                       "pipenv", "bundle", "rake", "cargo", "go", "air", "nodemon", "watchexec",
                                       "turbo", "nx", "concurrently", "foreman", "overmind", "honcho", "mix", "gradle",
                                       "java", "php", "dotnet"]

    struct Info {
        let ppid: Int32
        let name: String
        let cwd: String?
    }

    /// The listening process and the runners above it in the same folder, outermost first.
    /// `together` are other listening processes being stopped at the same time, so a runner
    /// they share (`concurrently "vite" "uvicorn"`) can go too.
    static func chain(_ pid: Int32, together: Set<Int32> = []) -> [Int32] {
        let others = Set(Scanner.listeningPids()).subtracting(together).subtracting([pid])
        return chain(pid, otherListeners: others, info: info)
    }

    /// The same, with process information passed in, for tests.
    static func chain(_ pid: Int32, otherListeners: Set<Int32>, info: (Int32) -> Info?) -> [Int32] {
        // Runners that another server still runs under: stopping them would stop that server too
        var shared = Set<Int32>()
        for other in otherListeners {
            var current = other
            for _ in 0..<8 {
                guard let parent = info(current)?.ppid, parent > 1 else { break }
                shared.insert(parent)
                current = parent
            }
        }

        var result = [pid]
        let cwd = info(pid)?.cwd
        var current = pid
        for _ in 0..<4 {
            guard let parent = info(current)?.ppid, parent > 1, let parentInfo = info(parent) else { break }
            let name = parentInfo.name.lowercased()   // Xcode's Python is "Python"
            let isRunner = runners.contains(name) || name.hasPrefix("python") || name.hasPrefix("ruby")
            guard isRunner, parentInfo.cwd == cwd, !shared.contains(parent) else { break }
            result.insert(parent, at: 0)
            current = parent
        }
        return result
    }

    static func info(_ pid: Int32) -> Info? {
        guard let bsd = Scanner.bsdInfo(pid) else { return nil }
        let name = withUnsafeBytes(of: bsd.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return Info(ppid: Int32(bsd.pbi_ppid), name: name, cwd: Scanner.workingDirectory(pid))
    }

    static func stop(_ pid: Int32, force: Bool, together: Set<Int32> = []) {
        for p in chain(pid, together: together) { kill(p, force ? SIGKILL : SIGTERM) }
    }

    /// For the command line: stops the server and waits up to `timeout` for it to exit.
    static func stopAndWait(_ server: Server, force: Bool, together: Set<Int32> = [], timeout: TimeInterval = 4) -> Bool {
        if let name = server.container {
            Docker.stop(name, force: force)
            return !scanServers().contains { $0.container == name }
        }
        guard let pid = server.pid else { return false }
        stop(pid, force: force, together: together)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !Scanner.isAlive(pid) { return true }
            usleep(100_000)
        }
        return !Scanner.isAlive(pid)
    }
}
