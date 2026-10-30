// Finds every TCP socket in LISTEN state and the process that owns it, by asking
// the kernel directly through libproc (the same source lsof uses), without spawning anything.
// Only processes owned by the current user are visible, which covers dev servers.

import Darwin
import Foundation

/// A listening socket.
struct Listener: Hashable, Codable {
    let port: UInt16
    /// The address it's bound to: "127.0.0.1", "::1", or "*" for all interfaces.
    let address: String

    /// Reachable from other devices on the network, not just this Mac.
    var exposed: Bool {
        !(address.hasPrefix("127.") || address == "::1" || address == "::ffff:127.0.0.1")
    }
}

/// A process that listens on at least one port.
struct Proc {
    let pid: Int32
    let ppid: Int32
    let name: String
    let path: String
    let args: [String]
    let cwd: String?
    let started: Date
    let memory: UInt64
    let listeners: [Listener]
}

enum Scanner {
    static func listeningProcesses() -> [Proc] {
        allPids().compactMap { pid in
            let ls = listeners(pid)
            return ls.isEmpty ? nil : process(pid, listeners: ls)
        }
    }

    /// Processes with at least one listening socket, without reading anything else about them.
    static func listeningPids() -> [Int32] {
        allPids().filter { !listeners($0).isEmpty }
    }

    static func allPids() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return pids.prefix(Int(max(0, n))).filter { $0 > 0 }
    }

    /// The process's TCP listening sockets, one per port and address.
    static func listeners(_ pid: Int32) -> [Listener] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
        guard got > 0 else { return [] }

        var result: [Listener] = []
        for fd in fds.prefix(Int(got) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize) == infoSize,
                  info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }

            let ini = tcp.tcpsi_ini
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: ini.insi_lport))
            var address: String
            if ini.insi_vflag & UInt8(INI_IPV4) != 0 {
                var a = ini.insi_laddr.ina_46.i46a_addr4
                address = ntop(AF_INET, &a, Int(INET_ADDRSTRLEN))
                if address == "0.0.0.0" { address = "*" }
            } else {
                var a = ini.insi_laddr.ina_6
                address = ntop(AF_INET6, &a, Int(INET6_ADDRSTRLEN))
                if address == "::" { address = "*" }
            }
            let listener = Listener(port: port, address: address)
            if !result.contains(listener) { result.append(listener) }
        }
        return result
    }

    static func process(_ pid: Int32, listeners: [Listener]) -> Proc {
        let bsd = bsdInfo(pid)
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathLength = proc_pidpath(pid, &path, UInt32(path.count))
        let fullPath = pathLength > 0 ? String(cString: path) : ""
        let name = bsd.map { cString($0.pbi_name) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? bsd.map { cString($0.pbi_comm) } ?? (fullPath as NSString).lastPathComponent
        return Proc(
            pid: pid,
            ppid: Int32(bsd?.pbi_ppid ?? 0),
            name: name,
            path: fullPath,
            args: arguments(pid),
            cwd: workingDirectory(pid),
            started: bsd.map { Date(timeIntervalSince1970: Double($0.pbi_start_tvsec) + Double($0.pbi_start_tvusec) / 1e6) } ?? Date(),
            memory: footprint(pid),
            listeners: listeners.sorted { ($0.port, $0.address) < ($1.port, $1.address) })
    }

    static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = cString(info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    /// Memory as Activity Monitor shows it.
    static func footprint(_ pid: Int32) -> UInt64 {
        var usage = rusage_info_v2()
        let ok = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) == 0
            }
        }
        return ok ? usage.ri_phys_footprint : 0
    }

    /// The command line, from KERN_PROCARGS2: argc, the executable path, padding, then the arguments.
    static func arguments(_ pid: Int32) -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return [] }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = 4
        while i < size && buffer[i] != 0 { i += 1 }   // executable path
        while i < size && buffer[i] == 0 { i += 1 }   // padding
        var args: [String] = []
        while args.count < argc && i < size {
            let start = i
            while i < size && buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    /// Running, as opposed to gone or exited and waiting for its parent to collect it (a zombie).
    static func isAlive(_ pid: Int32) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        return bsdInfo(pid).map { $0.pbi_status != UInt32(SZOMB) } ?? false   // no info: a zombie
    }

    /// Whether anything at all holds the port, including processes Portside can't see
    /// (other users, root): try to bind it ourselves on the any and loopback addresses.
    /// SO_REUSEADDR lets the bind ignore closed connections lingering in TIME_WAIT, which
    /// aren't listeners, while a real listener on the same address still refuses it.
    static func portInUse(_ port: UInt16) -> Bool {
        func v4(_ ip: UInt32) -> sockaddr_in {
            var a = sockaddr_in()
            a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            a.sin_family = sa_family_t(AF_INET)
            a.sin_port = port.bigEndian
            a.sin_addr.s_addr = ip.bigEndian
            return a
        }
        func v6(_ ip: in6_addr) -> sockaddr_in6 {
            var a = sockaddr_in6()
            a.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            a.sin6_family = sa_family_t(AF_INET6)
            a.sin6_port = port.bigEndian
            a.sin6_addr = ip
            return a
        }
        var any4 = v4(INADDR_ANY), loop4 = v4(INADDR_LOOPBACK)
        var any6 = v6(in6addr_any), loop6 = v6(in6addr_loopback)
        return [tryBind(&any4, AF_INET), tryBind(&loop4, AF_INET), tryBind(&any6, AF_INET6), tryBind(&loop6, AF_INET6)]
            .contains(EADDRINUSE)
    }

    /// Binds a throwaway socket to the address; returns errno on failure, 0 on success.
    private static func tryBind<T>(_ addr: inout T, _ family: Int32) -> Int32 {
        let fd = socket(family, SOCK_STREAM, 0)
        guard fd >= 0 else { return errno }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        if family == AF_INET6 { setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &yes, socklen_t(MemoryLayout<Int32>.size)) }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<T>.size)) }
        }
        return result == 0 ? 0 : errno
    }

    /// This Mac's address on the local network (Wi-Fi or Ethernet), for "open on your phone" URLs.
    static func lanAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [(String, String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  ifa.ifa_flags & UInt32(IFF_UP) != 0, ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var a = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            candidates.append((name, ntop(AF_INET, &a, Int(INET_ADDRSTRLEN))))
        }
        return candidates.sorted { $0.0 < $1.0 }.first?.1
    }

    private static func ntop<T>(_ family: Int32, _ addr: inout T, _ length: Int) -> String {
        var buffer = [CChar](repeating: 0, count: length)
        let ok = withUnsafeBytes(of: &addr) { inet_ntop(family, $0.baseAddress, &buffer, socklen_t(length)) != nil }
        return ok ? String(cString: buffer) : "?"
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
