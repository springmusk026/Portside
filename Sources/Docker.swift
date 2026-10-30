// Container names for published ports, from `docker ps`. Works with Docker Desktop,
// OrbStack and Colima, whichever the docker CLI points at. Only run when a container
// runtime is listening, and cached briefly so the scan loop doesn't spawn it every time.

import Foundation

struct DockerContainer: Equatable {
    let name: String
    let image: String
    let status: String
    let hostPorts: Set<UInt16>
}

enum Docker {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: (date: Date, containers: [DockerContainer])?

    static var cli: String? {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin/docker", "/usr/local/bin/docker", "\(home)/.orbstack/bin/docker",
                "/Applications/Docker.app/Contents/Resources/bin/docker", "\(home)/.docker/bin/docker"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func containers(maxAge: TimeInterval = 8) -> [DockerContainer] {
        lock.lock()
        if let cache, Date().timeIntervalSince(cache.date) < maxAge { lock.unlock(); return cache.containers }
        lock.unlock()
        let fresh = cli.flatMap { run($0, ["ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"]) }
            .map(parse) ?? []
        lock.lock()
        cache = (Date(), fresh)
        lock.unlock()
        return fresh
    }

    static func invalidate() {
        lock.lock(); cache = nil; lock.unlock()
    }

    static func stop(_ name: String, force: Bool) {
        guard let cli else { return }
        _ = run(cli, [force ? "kill" : "stop", name], timeout: 20)
        invalidate()
    }

    /// Parses `docker ps` lines. Ports look like "0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp".
    static func parse(_ output: String) -> [DockerContainer] {
        output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4 else { return nil }
            var ports = Set<UInt16>()
            for mapping in f[3].split(separator: ",") {
                guard let arrow = mapping.range(of: "->") else { continue }
                let host = mapping[..<arrow.lowerBound]
                guard let colon = host.lastIndex(of: ":") else { continue }
                let spec = host[host.index(after: colon)...]
                // A range like 8000-8002
                let bounds = spec.split(separator: "-").compactMap { UInt16($0) }
                if let lo = bounds.first { (lo...(bounds.last ?? lo)).forEach { ports.insert($0) } }
            }
            return DockerContainer(name: f[0], image: f[1], status: f[2], hostPorts: ports)
        }
    }

    private static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 4) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { process.waitUntilExit(); done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut { process.terminate(); return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
