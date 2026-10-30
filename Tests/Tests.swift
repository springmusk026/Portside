// Portside's tests: the pure parts (classifying, parsing, stopping, grouping) and the panel's
// real layout. No XCTest, so they run with just the command line tools: ./test.sh

import AppKit
import SwiftUI

@main
struct Tests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        for (name, test) in all {
            current = name
            test()
        }
        print(failures == 0 ? "All \(all.count) tests passed." : "\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }

    nonisolated(unsafe) static var current = ""
    nonisolated(unsafe) static var failures = 0

    @MainActor
    static let all: [(String, () -> Void)] = [
        ("classify", classify),
        ("tokens", tokens),
        ("stop chain", stopChain),
        ("docker parse", dockerParse),
        ("change tracker", changeTracker),
        ("project", project),
        ("formatting", formatting),
        ("sections", sections),
        ("hide and pin", hideAndPin),
        ("panel layout", panelLayout),
    ]
}

func expect<T: Equatable>(_ actual: T, _ expected: T, _ note: String = "", line: Int = #line) {
    guard actual != expected else { return }
    Tests.failures += 1
    print("✗ \(Tests.current) (line \(line))\(note.isEmpty ? "" : ", \(note)"): got \(actual), expected \(expected)")
}

func proc(_ path: String, _ args: [String], name: String? = nil) -> Proc {
    Proc(pid: 1000, ppid: 1, name: name ?? (path as NSString).lastPathComponent, path: path, args: args, cwd: nil,
         started: Date(), memory: 0, listeners: [Listener(port: 3000, address: "127.0.0.1")])
}

// MARK: - Classifying

func classify() {
    func c(_ path: String, _ args: [String], name: String? = nil) -> String {
        let (kind, detail) = Classifier.classify(proc(path, args, name: name))
        return "\(kind.rawValue) \(detail)"
    }
    expect(c("/usr/local/bin/node", ["next-server (v15.4.2)"]), "dev Next.js")
    expect(c("/usr/local/bin/node", ["node", "/p/node_modules/.bin/vite", "--port", "5173"]), "dev Vite")
    expect(c("/usr/local/bin/node", ["node", "node_modules/.bin/storybook", "dev"]), "dev Storybook")
    expect(c("/usr/bin/python3", ["python3", "manage.py", "runserver"]), "dev Django")
    expect(c("/usr/bin/python3", ["python3", "-m", "http.server", "8000"]), "dev Python http.server")
    expect(c("/opt/homebrew/opt/postgresql@17/bin/postgres", ["postgres", "-D", "x"]), "service PostgreSQL")
    expect(c("/usr/bin/ssh", ["ssh", "-L", "5432:db:5432", "bastion"]), "service SSH tunnel")
    expect(c("/Applications/Spotify.app/Contents/MacOS/Spotify", ["Spotify"]), "app Spotify")
    expect(c("/Applications/Xcode.app/Contents/Developer/usr/bin/python3", ["python3", "app.py"]), "dev Python")
    expect(c("/Applications/Docker.app/x/com.docker.backend", [], name: "com.docker.backend"), "container Docker")
    expect(c("/Users/me/p/target/debug/api", ["api"]), "dev Rust")
}

func tokens() {
    let t = Classifier.tokens(["node", "/p/node_modules/@sveltejs/kit/svelte-kit.js", "dev"])
    expect(t.contains("@sveltejs/kit"), true)
    expect(t.contains("svelte-kit"), true)
    expect(t.contains("dev"), true)
}

// MARK: - Stopping

func stopChain() {
    // launchd → zsh → turbo (repo) → npm (apps/web) → node → next-server (listens)
    //                               → npm (apps/api) → uvicorn (listens)
    // launchd → zsh → concurrently (repo) → vite (listens), uvicorn (listens)
    let tree: [Int32: Killer.Info] = [
        10: .init(ppid: 1, name: "zsh", cwd: "/r"),
        100: .init(ppid: 10, name: "turbo", cwd: "/r"),
        200: .init(ppid: 100, name: "npm", cwd: "/r/web"),
        201: .init(ppid: 200, name: "node", cwd: "/r/web"),
        202: .init(ppid: 201, name: "next-server", cwd: "/r/web"),
        300: .init(ppid: 100, name: "npm", cwd: "/r/api"),
        301: .init(ppid: 300, name: "python3.12", cwd: "/r/api"),
        400: .init(ppid: 10, name: "concurrently", cwd: "/r"),
        401: .init(ppid: 400, name: "node", cwd: "/r"),
        402: .init(ppid: 400, name: "python3", cwd: "/r"),
        500: .init(ppid: 10, name: "Python", cwd: "/x"),
        501: .init(ppid: 500, name: "Python", cwd: "/x"),
    ]
    let info = { (pid: Int32) in tree[pid] }
    // The web server's own runners go; turbo is in another folder and runs the api too
    expect(Killer.chain(202, otherListeners: [301, 401, 402], info: info), [200, 201, 202])
    // concurrently also runs the other server: keep it
    expect(Killer.chain(401, otherListeners: [202, 301, 402], info: info), [401], "shared runner")
    // ...unless both are stopped together
    expect(Killer.chain(401, otherListeners: [202, 301], info: info), [400, 401], "stopped together")
    // Xcode's Python names itself "Python"
    expect(Killer.chain(501, otherListeners: [], info: info), [500, 501], "capitalized runner")
    // Never above a non-runner
    expect(Killer.chain(301, otherListeners: [], info: info), [300, 301])
}

// MARK: - Docker

func dockerParse() {
    let out = """
    acme-db-1\tpostgres:16\tUp 3 hours\t0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp\t/Users/me/acme
    web\tnginx\tUp 1 minute\t127.0.0.1:8000-8002->80-82/tcp\t
    worker\tbusybox\tUp 2 days\t\t
    """
    let c = Docker.parse(out)
    expect(c.count, 3)
    expect(c[0].hostPorts, [5432])
    expect(c[0].composeDirectory, "/Users/me/acme")
    expect(c[1].hostPorts, [8000, 8001, 8002])
    expect(c[1].composeDirectory, nil)
    expect(c[2].hostPorts, [])
    // Older output without the label column still parses
    expect(Docker.parse("a\tb\tUp\t0.0.0.0:80->80/tcp").first?.hostPorts, [80])
}

// MARK: - Notifications

func changeTracker() {
    let web = Server(id: "pid:1", kind: .dev, title: "web", detail: "Vite", ports: [Listener(port: 5173, address: "::1")])
    var t = ChangeTracker()
    expect(t.update([], initial: true).count, 0)
    expect(t.update([web], initial: false).count, 0, "seen once")
    expect(t.update([web], initial: false).count, 1, "seen twice: started")
    expect(t.update([], initial: false).count, 0, "missing once")
    expect(t.update([web], initial: false).count, 0, "back: a hot reload")
    t.expectStop(web.key)
    expect(t.update([], initial: false).count, 0, "stopped from Portside")
}

// MARK: - Projects

func project() {
    let fm = FileManager.default
    let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("portside-tests-\(getpid())")
    defer { try? fm.removeItem(at: base) }
    let web = base.appendingPathComponent("acme/apps/web")
    try? fm.createDirectory(at: web.appendingPathComponent("src"), withIntermediateDirectories: true)
    try? fm.createDirectory(at: base.appendingPathComponent("acme/.git"), withIntermediateDirectories: true)
    fm.createFile(atPath: web.appendingPathComponent("package.json").path, contents: Data("{}".utf8))

    let p = Project.find(from: web.appendingPathComponent("src").path)
    expect(p?.name, "web")
    expect(p?.root, base.appendingPathComponent("acme").path)
    expect(Project.root(of: base.path), base.path, "no repository")
    expect(Project.find(from: "/"), nil)
}

func formatting() {
    expect(fmtUptime(42), "42s")
    expect(fmtUptime(125 * 60), "2h 05m")
    expect(fmtUptime(86_400 + 4 * 3600), "1d 04h")
    expect(fmtMemory(96_000_000), "92 MB")
    expect(dockerUptime("Up 3 hours"), "3 hours")
}

// MARK: - The panel

@MainActor
func sections() {
    let store = Demo.store()
    expect(store.sections(store.visible, byProject: false).map(\.title), ["Dev servers", "Services", "Containers"])
    let projects = store.sections(store.visible, byProject: true)
    expect(projects.map(\.title), ["acme", "blog", "Other"])
    expect(projects[0].servers.map(\.title), ["web", "ui", "api", "acme-redis-1"])
    expect(projects[2].servers.map(\.title), ["PostgreSQL", "Ollama"])
    let web = store.visible.first { $0.title == "web" }!
    expect(store.project(of: web).count, 4)
}

@MainActor
func hideAndPin() {
    let store = Demo.store()
    let blog = store.visible.first { $0.title == "blog" }!
    store.setPinned(blog, true)
    expect(store.visible.first?.title, "blog", "pinned first")
    store.setHidden(blog, true)
    expect(store.visible.contains { $0.title == "blog" }, false, "hidden")
    expect(store.apps.contains { $0.title == "blog" }, true, "listed with the apps")
    store.unhide(blog.nameKey)
    expect(store.visible.contains { $0.title == "blog" }, true, "unhidden")
}

/// The panel's height must not depend on the height it's offered. 1.0.1's ViewThatFits fell back
/// to a ScrollView, which takes whatever it's given: the menu bar window sized itself against it and
/// collapsed to the search field. That code measured 227 points by itself but 622 when offered more.
@MainActor
func panelLayout() {
    for (name, store) in [("one server", PortStore(servers: Demo.servers.filter { $0.title == "web" })),
                          ("demo", Demo.store())] {
        let controller = NSHostingController(rootView: PanelView().environmentObject(store))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        for _ in 0..<5 {
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        let preferred = controller.preferredContentSize.height
        let offeredMore = controller.sizeThatFits(in: CGSize(width: 360, height: 5000)).height
        let offeredLess = controller.sizeThatFits(in: CGSize(width: 360, height: 150)).height
        expect(offeredMore, preferred, "\(name): offered more room")
        expect(offeredLess, preferred, "\(name): offered less room")
        expect(preferred > (name == "demo" ? 450 : 200), true, "\(name): height \(Int(preferred))")
        window.close()
    }
}
