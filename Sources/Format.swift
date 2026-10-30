import Foundation

/// Fixed-width durations so values don't jitter as they tick: "45s", "12m", "2h 05m", "3d 04h".
func fmtUptime(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds))
    switch s {
    case ..<60:      return "\(s)s"
    case ..<3600:    return "\(s / 60)m"
    case ..<86_400:  return String(format: "%dh %02dm", s / 3600, s % 3600 / 60)
    default:         return String(format: "%dd %02dh", s / 86_400, s % 86_400 / 3600)
    }
}

/// "Up 3 hours" → "3 hours"; Docker's own wording, which is already readable.
func dockerUptime(_ status: String) -> String {
    status.hasPrefix("Up ") ? String(status.dropFirst(3)) : status
}

func fmtMemory(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1_048_576
    return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : "\(Int(mb.rounded())) MB"
}

func abbreviate(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
