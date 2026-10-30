import Foundation

/// Made-up servers for screenshots: a typical monorepo, a database or two, a container.
enum Demo {
    @MainActor
    static func store(stopping: [String: StopState] = [:], pinned: Set<String> = []) -> PortStore {
        PortStore(servers: servers, stopping: stopping, pinned: pinned)
    }

    static var servers: [Server] {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let local = { (port: UInt16) in [Listener(port: port, address: "127.0.0.1"), Listener(port: port, address: "::1")] }
        let all = { (port: UInt16) in [Listener(port: port, address: "*")] }
        let home = NSHomeDirectory()
        return Classifier.sorted([
            Server(id: "pid:41233", kind: .dev, title: "web", detail: "Next.js", ports: local(3000), pid: 41233,
                   command: "next-server (v15.4.2)", directory: "\(home)/Projects/acme/apps/web",
                   started: ago(125), memory: 431_000_000, group: "\(home)/Projects/acme"),
            Server(id: "pid:41301", kind: .dev, title: "api", detail: "Uvicorn", ports: all(8000), pid: 41301,
                   command: "python -m uvicorn main:app --reload --host 0.0.0.0", directory: "\(home)/Projects/acme/api",
                   started: ago(47), memory: 96_000_000, group: "\(home)/Projects/acme"),
            Server(id: "pid:52011", kind: .dev, title: "ui", detail: "Storybook", ports: local(6006), pid: 52011,
                   command: "node node_modules/.bin/storybook dev -p 6006", directory: "\(home)/Projects/acme/packages/ui",
                   started: ago(18), memory: 512_000_000, group: "\(home)/Projects/acme"),
            Server(id: "pid:30988", kind: .dev, title: "blog", detail: "Astro", ports: local(4321), pid: 30988,
                   command: "node node_modules/.bin/astro dev", directory: "\(home)/Projects/blog",
                   started: ago(60 * 76 + 12), memory: 188_000_000, group: "\(home)/Projects/blog"),
            Server(id: "pid:812", kind: .service, title: "PostgreSQL", detail: "postgres", ports: local(5432), pid: 812,
                   command: "/opt/homebrew/opt/postgresql@17/bin/postgres -D /opt/homebrew/var/postgresql@17",
                   started: ago(60 * 26), memory: 24_000_000, source: "Homebrew"),
            Server(id: "pid:905", kind: .service, title: "Ollama", detail: "ollama", ports: local(11434), pid: 905,
                   command: "/Applications/Ollama.app/Contents/Resources/ollama serve",
                   started: ago(60 * 26), memory: 1_480_000_000, source: "Ollama.app"),
            Server(id: "container:acme-redis-1", kind: .container, title: "acme-redis-1", detail: "redis:7-alpine",
                   ports: all(6379), container: "acme-redis-1", command: "docker acme-redis-1", status: "Up 2 hours", group: "\(home)/Projects/acme"),
            Server(id: "pid:648", kind: .app, title: "ControlCenter", detail: "AirPlay Receiver",
                   ports: all(5000) + all(7000), pid: 648, started: ago(60 * 50), memory: 38_000_000, source: "macOS"),
            Server(id: "pid:1204", kind: .app, title: "Figma", detail: "Figma Agent", ports: local(44950), pid: 1204,
                   started: ago(60 * 50), memory: 21_000_000),
            Server(id: "pid:1388", kind: .app, title: "Spotify", detail: "Spotify", ports: all(57621), pid: 1388,
                   started: ago(60 * 7), memory: 210_000_000),
        ])
    }
}
