// What Portside shows: listening processes turned into named servers.
// A process becomes a dev server, a service (database, tunnel, local AI), a container
// (resolved through the docker CLI) or an app, and gets a project name from its folder.

import Foundation

enum Kind: String, Codable, CaseIterable {
    case dev, service, container, app

    var section: String {
        switch self {
        case .dev:       return "Dev servers"
        case .service:   return "Services"
        case .container: return "Containers"
        case .app:       return "Apps & system"
        }
    }

    /// Dev servers, services and containers can be stopped from Portside; apps can't.
    var stoppable: Bool { self != .app }
}

struct Server: Identifiable, Codable, Equatable {
    /// "pid:123" or "container:name". Changes when a server restarts.
    let id: String
    let kind: Kind
    /// Project, container or app name.
    let title: String
    /// Framework, image or runtime: "Next.js", "postgres:16", "Python".
    let detail: String
    let ports: [Listener]
    var pid: Int32? = nil
    var container: String? = nil
    var command: String = ""
    /// The project folder, or the working directory when there's no project.
    var directory: String? = nil
    var started: Date? = nil
    var memory: UInt64? = nil
    /// Docker's own status ("Up 3 hours"), used instead of `started` for containers.
    var status: String? = nil
    /// Where the program comes from when there's no project folder: "Homebrew", "Ollama.app".
    var source: String? = nil
    /// The repository (or Compose folder) it belongs to, shared by a project's servers and containers.
    var group: String? = nil

    var primaryPort: UInt16 { ports.first?.port ?? 0 }
    var exposed: Bool { ports.contains { $0.exposed } }
    /// Unique ports, in order (a server often listens on both IPv4 and IPv6).
    var portNumbers: [UInt16] {
        ports.map(\.port).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Stays the same across restarts, for notifications.
    var key: String { "\(kind.rawValue)|\(title)|\(primaryPort)" }

    /// Stays the same across restarts and port changes, for hiding and pinning.
    var nameKey: String { "\(kind.rawValue)|\(title)" }

    /// The group's display name: its folder's name.
    var groupName: String? { group.map { ($0 as NSString).lastPathComponent } }

    /// What "open" or "copy" gives: a URL for web servers, a connection string for databases.
    var url: String { address(host: "localhost") }

    func address(host: String) -> String {
        let port = primaryPort
        let probe = (detail + " " + title).lowercased()
        for (needle, scheme) in Catalog.schemes where probe.contains(needle) {
            return "\(scheme)://\(host):\(port)"
        }
        return "http://\(host):\(port)"
    }

    /// Whether opening it in a browser makes sense.
    var isWeb: Bool { url.hasPrefix("http") && kind != .app }

    /// Up for more than a day: possibly forgotten.
    func forgotten(now: Date) -> Bool {
        kind == .dev && started.map { now.timeIntervalSince($0) > 86_400 } ?? false
    }
}

// MARK: - Building servers from processes

enum Classifier {
    static func servers(from procs: [Proc], containers: [DockerContainer]) -> [Server] {
        var result: [Server] = []
        for proc in procs {
            if Catalog.containerHosts.contains(proc.name) || proc.path.contains("/OrbStack.app/") {
                // Docker Desktop, OrbStack and Colima forward container ports through one
                // process; show each container instead, and the rest under the process itself.
                var leftover = proc.listeners
                for c in containers {
                    let mine = proc.listeners.filter { c.hostPorts.contains($0.port) }
                    guard !mine.isEmpty else { continue }
                    leftover.removeAll { mine.contains($0) }
                    if result.contains(where: { $0.container == c.name }) { continue }
                    result.append(Server(id: "container:\(c.name)", kind: .container, title: c.name,
                                         detail: c.image, ports: mine, container: c.name,
                                         command: "docker \(c.name)", status: c.status,
                                         group: c.composeDirectory.map { Project.root(of: $0) }))
                }
                if !leftover.isEmpty { result.append(server(proc, listeners: leftover)) }
            } else {
                result.append(server(proc, listeners: proc.listeners))
            }
        }
        return sorted(result)
    }

    static func sorted(_ servers: [Server]) -> [Server] {
        servers.sorted {
            let a = Kind.allCases.firstIndex(of: $0.kind)!, b = Kind.allCases.firstIndex(of: $1.kind)!
            return a != b ? a < b : $0.primaryPort < $1.primaryPort
        }
    }

    static func server(_ proc: Proc, listeners: [Listener]) -> Server {
        let (kind, detail) = classify(proc)
        let project = kind == .dev || kind == .service ? Project.find(from: proc.cwd) : nil
        let title: String = {
            switch kind {
            case .container: return detail
            case .app:       return appName(proc)
            case .service:   return detail
            case .dev:       return project?.name ?? detail
            }
        }()
        let subtitle = kind == .service || kind == .container ? proc.name : detail
        let usefulCwd = proc.cwd.flatMap { $0 == "/" ? nil : $0 }
        return Server(id: "pid:\(proc.pid)", kind: kind, title: title, detail: subtitle, ports: listeners,
                      pid: proc.pid, command: proc.args.joined(separator: " "),
                      directory: project?.path ?? (kind == .app ? nil : usefulCwd),
                      started: proc.started, memory: proc.memory, source: origin(proc.path), group: project?.root)
    }

    static func origin(_ path: String) -> String? {
        if path.hasPrefix("/opt/homebrew/") || path.contains("/Cellar/") || path.hasPrefix("/usr/local/opt/") { return "Homebrew" }
        if path.contains("/.nvm/") || path.contains("/.volta/") || path.contains("/.local/share/mise/") { return nil }
        if let range = path.range(of: ".app/") {
            return (String(path[..<range.lowerBound]) as NSString).lastPathComponent + ".app"
        }
        return nil
    }

    static func classify(_ proc: Proc) -> (Kind, String) {
        let exe = (proc.path as NSString).lastPathComponent
        if Catalog.containerHosts.contains(proc.name) || proc.path.contains("/OrbStack.app/") {
            return (.container, proc.path.contains("OrbStack") ? "OrbStack" : proc.name == "limactl" ? "Colima" : "Docker")
        }
        if let service = Catalog.services[exe] ?? Catalog.services[proc.name] { return (.service, service) }
        let words = tokens(proc.args)
        let joined = proc.args.joined(separator: " ").lowercased()
        if exe == "ssh" && proc.args.contains(where: { $0.hasPrefix("-L") || $0.hasPrefix("-D") }) {
            return (.service, "SSH tunnel")
        }
        for (needle, name) in Catalog.argServices where joined.contains(needle) && ["java", "beam.smp"].contains(exe) {
            return (.service, name)
        }
        if isApp(proc) { return (.app, appName(proc)) }
        if joined.contains("next-server") { return (.dev, "Next.js") }
        for (token, name) in Catalog.frameworks where words.contains(token) { return (.dev, name) }
        if joined.contains("manage.py") && joined.contains("runserver") { return (.dev, "Django") }
        if joined.contains("http.server") { return (.dev, "Python http.server") }
        if proc.path.contains("/go-build") { return (.dev, "Go") }
        if proc.path.contains("/target/debug/") || proc.path.contains("/target/release/") { return (.dev, "Rust") }
        return (.dev, runtime(exe))
    }

    /// Words worth matching in a command line: each argument's file name without
    /// extension, and package names under node_modules ("@sveltejs/kit").
    static func tokens(_ args: [String]) -> Set<String> {
        var out = Set<String>()
        for arg in args {
            let lower = arg.lowercased()
            for part in lower.split(separator: " ") {
                let base = ((String(part) as NSString).lastPathComponent as NSString).deletingPathExtension
                out.insert(base)
            }
            var rest = Substring(lower)
            while let r = rest.range(of: "node_modules/") {
                rest = rest[r.upperBound...]
                let parts = rest.split(separator: "/", maxSplits: 2)
                if let first = parts.first {
                    out.insert(first.hasPrefix("@") && parts.count > 1 ? "\(first)/\(parts[1])" : String(first))
                }
            }
        }
        return out
    }

    static func runtime(_ exe: String) -> String {
        let lower = exe.lowercased()
        if lower.hasPrefix("python") { return "Python" }
        if lower.hasPrefix("ruby") { return "Ruby" }
        return Catalog.runtimes[lower] ?? exe
    }

    /// Inside an app bundle or part of macOS. Language runtimes are never apps, even when
    /// they live in a bundle: /usr/bin/python3 runs from Xcode.app, Homebrew's Python from Python.app.
    static func isApp(_ proc: Proc) -> Bool {
        let exe = (proc.path as NSString).lastPathComponent.lowercased()
        if Catalog.runtimePrefixes.contains(where: { exe.hasPrefix($0) }) { return false }
        let path = proc.path
        if path.contains(".framework/") || path.contains("/Contents/Developer/") { return false }
        return path.contains(".app/") || ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    /// The outermost app bundle's name ("Visual Studio Code" for its helpers), or the process name.
    static func appName(_ proc: Proc) -> String {
        if let range = proc.path.range(of: ".app/") {
            return (String(proc.path[..<range.lowerBound]) as NSString).lastPathComponent
        }
        return proc.name
    }
}

// MARK: - Projects

struct Project: Equatable {
    let name: String
    let path: String
    /// The repository it's part of (the nearest folder with `.git`), or `path` outside one.
    let root: String

    static let markers = ["package.json", "pyproject.toml", "Gemfile", "go.mod", "Cargo.toml", "composer.json",
                          "mix.exs", "deno.json", "manage.py", "requirements.txt", "pom.xml", "build.gradle",
                          "build.gradle.kts", "Package.swift", ".git"]

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: (date: Date, project: Project?)] = [:]

    /// The nearest folder at or above `cwd` that looks like a project, stopping at the home folder.
    /// Cached for a minute: the scan asks every 3 seconds, and projects rarely move.
    static func find(from cwd: String?) -> Project? {
        guard let cwd, cwd != "/" else { return nil }
        lock.lock()
        if let hit = cache[cwd], Date().timeIntervalSince(hit.date) < 60 { lock.unlock(); return hit.project }
        lock.unlock()
        let project = lookup(cwd)
        lock.lock()
        if cache.count > 500 { cache.removeAll() }
        cache[cwd] = (Date(), project)
        lock.unlock()
        return project
    }

    private static func lookup(_ cwd: String) -> Project? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd)
        while dir.path != NSHomeDirectory() && dir.path != "/" {
            if markers.contains(where: { fm.fileExists(atPath: dir.appendingPathComponent($0).path) }) {
                return Project(name: dir.lastPathComponent, path: dir.path, root: root(of: dir.path))
            }
            dir.deleteLastPathComponent()
        }
        return cwd == NSHomeDirectory() ? nil : Project(name: (cwd as NSString).lastPathComponent, path: cwd, root: root(of: cwd))
    }

    /// The nearest folder at or above `path` with a `.git`, below the home folder; otherwise `path`.
    static func root(of path: String) -> String {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: path)
        while dir.path != NSHomeDirectory() && dir.path != "/" {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir.path }
            dir.deleteLastPathComponent()
        }
        return path
    }
}

// MARK: - Known names

enum Catalog {
    /// Processes that forward container ports.
    static let containerHosts: Set<String> = ["com.docker.backend", "com.docker.vpnkit", "vpnkit-bridge",
                                              "com.docker.supervisor", "OrbStack Helper", "limactl", "gvproxy"]

    static let services: [String: String] = [
        "postgres": "PostgreSQL", "mysqld": "MySQL", "mariadbd": "MariaDB", "redis-server": "Redis",
        "valkey-server": "Valkey", "mongod": "MongoDB", "memcached": "Memcached", "ollama": "Ollama",
        "influxd": "InfluxDB", "clickhouse": "ClickHouse", "clickhouse-server": "ClickHouse",
        "nats-server": "NATS", "minio": "MinIO", "caddy": "Caddy", "nginx": "nginx", "httpd": "Apache",
        "meilisearch": "Meilisearch", "typesense-server": "Typesense", "temporal": "Temporal",
        "etcd": "etcd", "consul": "Consul", "vault": "Vault", "mailpit": "Mailpit", "mailhog": "MailHog",
        "cloudflared": "Cloudflare Tunnel", "ngrok": "ngrok", "tailscaled": "Tailscale", "surreal": "SurrealDB",
        "qdrant": "Qdrant", "llama-server": "llama.cpp", "lms": "LM Studio", "valkey": "Valkey",
    ]

    /// Services that run on a shared runtime (the JVM, Erlang), found by their command line.
    static let argServices: [(String, String)] = [
        ("elasticsearch", "Elasticsearch"), ("opensearch", "OpenSearch"), ("kafka", "Kafka"),
        ("zookeeper", "ZooKeeper"), ("rabbit", "RabbitMQ"), ("couchdb", "CouchDB"), ("cassandra", "Cassandra"),
        ("keycloak", "Keycloak"),
    ]

    /// Command-line words to framework names, in priority order (a Storybook started
    /// through webpack is Storybook).
    static let frameworks: [(String, String)] = [
        ("storybook", "Storybook"), ("@storybook/cli", "Storybook"), ("next", "Next.js"),
        ("nuxt", "Nuxt"), ("nuxi", "Nuxt"), ("astro", "Astro"), ("@remix-run/dev", "Remix"), ("remix", "Remix"),
        ("react-router", "React Router"), ("@sveltejs/kit", "SvelteKit"), ("svelte-kit", "SvelteKit"),
        ("@angular/cli", "Angular"), ("ng", "Angular"), ("vitepress", "VitePress"), ("vinxi", "Vinxi"),
        ("@tanstack/start", "TanStack Start"), ("vite", "Vite"), ("gatsby", "Gatsby"),
        ("docusaurus", "Docusaurus"), ("@docusaurus/core", "Docusaurus"), ("expo", "Expo"),
        ("react-native", "Metro"), ("metro", "Metro"), ("wrangler", "Wrangler"), ("parcel", "Parcel"),
        ("eleventy", "Eleventy"), ("@11ty/eleventy", "Eleventy"), ("@nestjs/cli", "NestJS"), ("nest", "NestJS"),
        ("@rsbuild/core", "Rsbuild"), ("rsbuild", "Rsbuild"), ("rspack", "Rspack"),
        ("webpack-dev-server", "webpack"), ("webpack", "webpack"), ("prisma", "Prisma Studio"),
        ("drizzle-kit", "Drizzle Studio"), ("convex", "Convex"), ("firebase", "Firebase emulators"),
        ("json-server", "json-server"),
        ("uvicorn", "Uvicorn"), ("fastapi", "FastAPI"), ("flask", "Flask"), ("gunicorn", "Gunicorn"),
        ("hypercorn", "Hypercorn"), ("granian", "Granian"), ("streamlit", "Streamlit"), ("gradio", "Gradio"),
        ("jupyter-lab", "Jupyter"), ("jupyter-notebook", "Jupyter"), ("jupyter", "Jupyter"),
        ("mkdocs", "MkDocs"), ("marimo", "marimo"), ("rails", "Rails"), ("puma", "Puma"), ("rackup", "Rack"),
        ("jekyll", "Jekyll"), ("hugo", "Hugo"), ("zola", "Zola"), ("artisan", "Laravel"), ("phx.server", "Phoenix"),
        ("trunk", "Trunk"), ("air", "Go (air)"), ("bootrun", "Spring Boot"), ("spring-boot", "Spring Boot"),
        // Generic runners last: a framework started through them wins
        ("http-server", "http-server"), ("serve", "serve"), ("nodemon", "nodemon"), ("tsx", "tsx"),
        ("ts-node", "ts-node"),
    ]

    static let runtimePrefixes = ["python", "ruby", "node", "bun", "deno", "php", "java", "dotnet", "beam.smp", "perl"]

    static let runtimes: [String: String] = [
        "node": "Node.js", "bun": "Bun", "deno": "Deno", "php": "PHP", "java": "Java", "dotnet": ".NET",
        "beam.smp": "Erlang", "go": "Go", "swift": "Swift",
    ]

    /// Connection-string schemes, matched against a server's name and detail.
    static let schemes: [(String, String)] = [
        ("postgres", "postgres"), ("mysql", "mysql"), ("mariadb", "mysql"), ("redis", "redis"),
        ("valkey", "redis"), ("mongo", "mongodb"), ("memcached", "memcached"), ("nats", "nats"),
        ("rabbitmq", "amqp"), ("kafka", "kafka"), ("ssh tunnel", "socks5"),
    ]
}
