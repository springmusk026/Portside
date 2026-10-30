import SwiftUI

/// Forces a state when rendering snapshots.
struct PanelPreview {
    var query = ""
    var hovered: String? = nil
    var showApps = false
    var confirmStopAll = false
}

struct PanelView: View {
    var preview: PanelPreview? = nil
    @EnvironmentObject private var store: PortStore
    @State private var query = ""
    @AppStorage("showApps") private var showApps = false
    @State private var confirmStopAll = false
    @FocusState private var searchFocused: Bool
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.openSettings) private var openSettings

    private var text: String { (preview?.query ?? query).trimmingCharacters(in: .whitespaces) }
    private var appsShown: Bool { preview?.showApps ?? showApps }

    /// "3000" or ":3000" in the search field means "who's on this port?"
    private var lookupPort: UInt16? {
        let digits = text.hasPrefix(":") ? String(text.dropFirst()) : text
        return UInt16(digits).flatMap { $0 > 0 ? $0 : nil }
    }

    private func matches(_ s: Server) -> Bool {
        guard !text.isEmpty else { return true }
        let q = text.lowercased()
        return [s.title, s.detail, s.directory ?? "", s.container ?? "", s.portNumbers.map(String.init).joined(separator: " ")]
            .contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header.entrance(0)
            searchField.entrance(1)
            if isSnapshot {
                content
            } else {
                ViewThatFits(in: .vertical) {
                    content
                    ScrollView { content }.scrollIndicators(.never)
                }
                .frame(maxHeight: 470)
            }
            footer.entrance(4)
        }
        .padding(Space.m)
        .frame(width: 360)
        .onAppear { searchFocused = true }
    }

    // MARK: Header

    private struct Summary {
        var text: String
        var color: Color
        var hollow = false
        var note: Text? = nil
    }

    private var summary: Summary {
        let servers = store.visible
        guard store.loaded else { return Summary(text: "Scanning…", color: .secondary, hollow: true) }
        let stuck = store.stopping.values.filter { $0 == .stuck }.count
        if stuck > 0 {
            return Summary(text: stuck == 1 ? "1 server didn't stop" : "\(stuck) servers didn't stop",
                           color: .critical, note: Text("Force quit it below."))
        }
        guard !servers.isEmpty else { return Summary(text: "Nothing running", color: .secondary, hollow: true) }
        var parts: [Text] = []
        let exposed = servers.filter(\.exposed).count
        if exposed > 0 { parts.append(Text("\(exposed) open to your network").foregroundColor(.caution)) }
        let forgotten = servers.filter { $0.forgotten(now: store.now) }.count
        if forgotten > 0 { parts.append(Text("\(forgotten) up for over a day")) }
        let note = parts.isEmpty ? nil : parts.dropFirst().reduce(parts[0]) { $0 + Text("  ·  ").foregroundColor(Color.primary.opacity(0.25)) + $1 }
        return Summary(text: "\(servers.count) running", color: .live, note: note)
    }

    private var header: some View {
        let s = summary
        return HStack(alignment: .top, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.xs) {
                    StatusDot(color: s.color, hollow: s.hollow)
                    Text(s.text).font(Typo.metric).contentTransition(.numericText())
                }
                if let note = s.note {
                    note.font(Typo.caption).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 15)
                        .help("“Open to your network”: listening on all interfaces, so other devices can connect.")
                }
            }
            Spacer()
            CircleButton(icon: "gearshape", help: "Settings") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: Search

    private var searchField: some View {
        let focused = searchFocused && !isSnapshot
        return HStack(spacing: Space.xs) {
            Image(systemName: lookupPort != nil ? "number" : "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(lookupPort != nil ? Color.harbor : .secondary)
                .frame(width: 14)
            if isSnapshot {
                Text(text.isEmpty ? "Filter, or type a port" : text)
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Filter, or type a port", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit(submit)
                    .onExitCommand { query = "" }
            }
            if !text.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear (Esc)")
            }
        }
        .font(Typo.body)
        .padding(.horizontal, Space.s)
        .frame(height: 30)
        .background(Capsule().fill(Color.surface))
        .overlay(Capsule().strokeBorder(focused ? Color.harbor.opacity(0.55) : Color.hairline, lineWidth: focused ? 1 : 0.5))
        .animation(Motion.quick, value: focused)
    }

    /// Return opens the only match.
    private func submit() {
        let hits = lookupPort.map { p in store.servers.filter { $0.portNumbers.contains(p) } }
            ?? store.visible.filter(matches)
        if hits.count == 1, let s = hits.first { s.isWeb ? store.open(s) : store.copy(s.url) }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if !store.loaded {
                EmptyView()
            } else if let port = lookupPort {
                PortLookupView(port: port, result: store.lookup(port), hovered: preview?.hovered)
                    .entrance(2)
            } else {
                let shown = store.visible.filter(matches)
                if store.visible.isEmpty {
                    emptyState.entrance(2)
                } else if shown.isEmpty {
                    Text("Nothing matches “\(text)”.").font(Typo.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, Space.xxs)
                }
                ForEach(Array([Kind.dev, .service, .container].enumerated()), id: \.element) { i, kind in
                    let rows = shown.filter { $0.kind == kind }
                    if !rows.isEmpty {
                        ServerSection(title: kind.section, servers: rows, hovered: preview?.hovered)
                            .entrance(2 + i)
                    }
                }
                appsSection.entrance(3)
            }
        }
    }

    private var emptyState: some View {
        Card {
            Text("Start a dev server, database or container and it shows up here within 3 seconds.")
                .font(Typo.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.xs) {
                ForEach(["npm run dev", "rails s", "docker compose up"], id: \.self) {
                    Text($0).font(Typo.mono).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.surface))
                }
            }
        }
    }

    @ViewBuilder private var appsSection: some View {
        let apps = store.apps.filter(matches)
        if !apps.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                Button {
                    withAnimation(Motion.spring) { showApps.toggle() }
                } label: {
                    HStack(spacing: Space.xxs) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(appsShown ? 90 : 0))
                            .frame(width: 12)
                        Text(apps.count == 1 ? "1 app or system process also listens" : "\(apps.count) apps and system processes also listen")
                        Spacer()
                    }
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                if appsShown {
                    ServerSection(title: nil, servers: apps, hovered: preview?.hovered)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        let devs = store.visible.filter { $0.kind == .dev && store.stopping[$0.id] == nil }
        let confirming = preview?.confirmStopAll ?? confirmStopAll
        return HStack(spacing: Space.xs) {
            if devs.count > 1 {
                FooterButton(title: confirming ? "Stop \(devs.count) dev servers?" : "Stop all dev servers",
                             icon: "stop.fill", tint: confirming ? .critical : nil) {
                    if confirming {
                        confirmStopAll = false
                        store.stopAll()
                    } else {
                        withAnimation(Motion.quick) { confirmStopAll = true }
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation(Motion.quick) { confirmStopAll = false }
                        }
                    }
                }
            }
            Spacer()
            FooterButton(title: "Quit", icon: nil) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

// MARK: - Sections and rows

struct ServerSection: View {
    let title: String?
    let servers: [Server]
    var hovered: String? = nil
    var highlightPort: UInt16? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let title {
                HStack(spacing: Space.xxs) {
                    Text(title).font(Typo.heading).foregroundStyle(.secondary)
                    Text("\(servers.count)").font(Typo.mono).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Space.xxs)
            }
            Card(padding: 0, spacing: 0) {
                ForEach(Array(servers.enumerated()), id: \.element.id) { i, server in
                    if i > 0 { Rectangle().fill(Color.hairline).frame(height: 0.5).padding(.leading, 31) }
                    ServerRow(server: server, forceHover: hovered == server.id, highlightPort: highlightPort)
                }
            }
        }
    }
}

struct ServerRow: View {
    let server: Server
    var forceHover = false
    var highlightPort: UInt16? = nil
    @EnvironmentObject private var store: PortStore
    @State private var hovering = false

    private var state: StopState? { store.stopping[server.id] }
    private var showActions: Bool { (hovering || forceHover) && state == nil }

    var body: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            dot.frame(width: 11, height: 17)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.title).font(Typo.title).lineLimit(1).layoutPriority(1)
                    Text(server.detail).font(Typo.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: Space.xs)
                    ports
                }
                .frame(height: 17)
                HStack(spacing: Space.xs) {
                    meta
                    Spacer(minLength: 0)
                    if showActions {
                        actions.transition(.opacity)
                    } else if state == .stuck {
                        Button { store.stop(server, force: true) } label: {
                            Text("Force quit").font(Typo.micro).foregroundStyle(Color.critical)
                                .padding(.horizontal, Space.xs).frame(height: 20)
                                .background(Capsule().fill(Color.critical.opacity(0.1)))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .frame(height: 20)
            }
        }
        .padding(.leading, Space.s)
        .padding(.trailing, Space.xs)
        .padding(.vertical, 6)
        .background((hovering || forceHover) ? Color.surface : .clear)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.quick) { hovering = h } }
        .onTapGesture(perform: primaryAction)
        .help(server.isWeb ? "Click to open \(server.url)" : server.kind == .app ? server.command : "Click to copy \(server.url)")
        .contextMenu { menu }
        .opacity(state == nil ? 1 : 0.75)
        .animation(Motion.quick, value: state)
    }

    private func primaryAction() {
        guard state == nil else { return }
        if server.isWeb { store.open(server) } else if server.kind != .app { store.copy(server.url) }
    }

    @ViewBuilder private var dot: some View {
        switch state {
        case .stopping:  StatusDot(color: .secondary, hollow: true)
        case .stuck:     StatusDot(color: .critical)
        case nil:        StatusDot(color: server.kind == .app ? Color.secondary.opacity(0.6) : .live)
        }
    }

    private var ports: some View {
        let numbers = server.portNumbers
        let shown = numbers.prefix(2).map { ":\($0)" }.joined(separator: " ")
        return HStack(spacing: Space.xxs) {
            if server.exposed {
                Badge(text: "LAN", tint: .caution)
                    .help("Listening on all interfaces: other devices on your network can reach it")
            }
            Text(shown)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(highlightPort.map { numbers.contains($0) } == true ? Color.harbor : .primary)
            if numbers.count > 2 {
                Text("+\(numbers.count - 2)").font(Typo.mono).foregroundStyle(.secondary)
                    .help(numbers.dropFirst(2).map { ":\($0)" }.joined(separator: " "))
            }
        }
        .fixedSize()
    }

    @ViewBuilder private var meta: some View {
        switch state {
        case .stopping:
            Text("Stopping…").font(Typo.mono).foregroundStyle(.secondary)
        case .stuck:
            Text("Still listening").font(Typo.mono).foregroundStyle(Color.critical)
        case nil:
            HStack(spacing: 0) {
                if let place = place {
                    Text(place).lineLimit(1).truncationMode(.middle)
                    Text("  ·  ").foregroundStyle(.tertiary).fixedSize()
                }
                facts.fixedSize()
            }
            .font(Typo.mono)
            .foregroundStyle(.secondary)
        }
    }

    private var place: String? {
        if let dir = server.directory { return abbreviate(dir) }
        if server.kind == .container { return server.container == server.title ? "docker" : server.container }
        return server.source ?? server.pid.map { "pid \($0)" }
    }

    private var facts: Text {
        let forgotten = server.forgotten(now: store.now)
        var up: String?
        if let status = server.status { up = dockerUptime(status) }
        else if let started = server.started { up = fmtUptime(store.now.timeIntervalSince(started)) }
        var text = Text(up ?? "").foregroundColor(forgotten ? .caution : .secondary)
        if let memory = server.memory, memory > 0, !showActions {
            text = text + Text("  ·  ").foregroundColor(Color.primary.opacity(0.25)) + Text(fmtMemory(memory))
        }
        return text
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 2) {
            if server.isWeb {
                RowAction(icon: "arrow.up.right", help: "Open \(server.url)") { store.open(server) }
            }
            if server.kind != .app {
                RowAction(icon: "doc.on.doc", help: "Copy \(server.url)", confirms: true) { store.copy(server.url) }
            }
            if server.exposed, server.isWeb, let lan = store.lanAddress {
                let url = server.address(host: lan)
                RowAction(icon: "iphone", help: "Copy \(url) to open it on another device", confirms: true) { store.copy(url) }
            }
            if server.directory != nil {
                RowAction(icon: "folder", help: "Show in Finder") { store.reveal(server) }
            }
            if server.kind.stoppable {
                RowAction(icon: "stop.fill", help: server.container != nil ? "Stop container" : "Stop (SIGTERM)", destructive: true) {
                    store.stop(server)
                }
            }
        }
    }

    @ViewBuilder private var menu: some View {
        if server.isWeb { Button("Open in Browser") { store.open(server) } }
        if server.kind != .app { Button("Copy \(server.url)") { store.copy(server.url) } }
        if server.exposed, server.isWeb, let lan = store.lanAddress {
            Button("Copy Network URL") { store.copy(server.address(host: lan)) }
        }
        if server.directory != nil {
            Button("Show in Finder") { store.reveal(server) }
            Button("Open in Terminal") { store.openInTerminal(server) }
        }
        Divider()
        if let pid = server.pid { Button("Copy PID \(pid)") { store.copy(String(pid)) } }
        if !server.command.isEmpty { Button("Copy Command") { store.copy(server.command) } }
        if server.kind.stoppable {
            Divider()
            Button("Stop") { store.stop(server) }
            Button("Force Quit") { store.stop(server, force: true) }
        }
    }
}

/// A small icon button that appears on a hovered row.
struct RowAction: View {
    let icon: String
    let help: String
    var destructive = false
    var confirms = false
    let action: () -> Void
    @State private var hovering = false
    @State private var done = false

    var body: some View {
        Button {
            action()
            if confirms {
                withAnimation(Motion.quick) { done = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(Motion.quick) { done = false }
                }
            }
        } label: {
            Image(systemName: done ? "checkmark" : icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(done ? Color.live : hovering ? (destructive ? Color.critical : .primary) : .secondary)
                .frame(width: 24, height: 20)
                .background(RoundedRectangle(cornerRadius: Radius.control)
                    .fill(hovering ? (destructive ? Color.critical.opacity(0.1) : Color.surface) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct FooterButton: View {
    let title: String
    let icon: String?
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xxs + 2) {
                if let icon { Image(systemName: icon).font(.system(size: 8.5, weight: .semibold)) }
                Text(title).contentTransition(.interpolate)
            }
            .font(Typo.caption.weight(.medium))
            .foregroundStyle(tint ?? (hovering ? .primary : .secondary))
            .padding(.horizontal, Space.xs)
            .frame(height: 24)
            .background(Capsule().fill(hovering || tint != nil ? (tint?.opacity(0.1) ?? Color.surface) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Port lookup

struct PortLookupView: View {
    let port: UInt16
    let result: PortLookup
    var hovered: String? = nil
    @EnvironmentObject private var store: PortStore

    var body: some View {
        switch result {
        case .free:
            Card(glow: .live) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.xs) {
                        StatusDot(color: .live, hollow: true)
                        Text("Port \(String(port)) is free").font(Typo.metric)
                    }
                    Text("Nothing is listening on it, on any interface.")
                        .font(Typo.caption).foregroundStyle(.secondary).padding(.leading, 15)
                }
            }
        case .hidden:
            Card(glow: .caution) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.xs) {
                        StatusDot(color: .caution)
                        Text("Port \(String(port)) is taken").font(Typo.metric)
                    }
                    Text("By a process owned by another user or root, which Portside can't see without admin rights.")
                        .font(Typo.caption).foregroundStyle(.secondary).padding(.leading, 15)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let command = "sudo lsof -nP -iTCP:\(port) -sTCP:LISTEN"
                HStack {
                    Text(command).font(Typo.mono).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    RowAction(icon: "doc.on.doc", help: "Copy command", confirms: true) { store.copy(command) }
                }
                .padding(.leading, 15)
            }
        case .held(let servers):
            let stoppable = servers.filter { $0.kind.stoppable && store.stopping[$0.id] == nil }
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.xs) {
                    StatusDot(color: .harbor)
                    Text("Port \(String(port)) is taken").font(Typo.metric)
                }
                .padding(.horizontal, Space.xxs)
                ServerSection(title: nil, servers: servers, hovered: hovered, highlightPort: port)
                if !stoppable.isEmpty {
                    PrimaryPill(title: "Free port \(String(port))",
                                detail: stoppable.count == 1 ? "stops \(stoppable[0].title)" : "stops \(stoppable.count) processes",
                                icon: "stop.fill") {
                        stoppable.forEach { store.stop($0) }
                    }
                }
            }
        }
    }
}
