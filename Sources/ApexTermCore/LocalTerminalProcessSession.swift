import Darwin

/// Identifies the independent POSIX session created for a local PTY and signals
/// every live job process group inside it. Interactive shells assign pipelines
/// and background jobs to separate process groups, so signaling only the shell's
/// group can otherwise leave orphaned jobs behind when a pane closes.
public struct LocalTerminalProcessSession: Sendable {
    public let sessionID: pid_t

    private let excludedSessionID: pid_t
    private let excludedProcessGroup: pid_t

    public init?(rootPID: pid_t) {
        guard rootPID > 0 else { return nil }
        let sessionID = Darwin.getsid(rootPID)
        let ownSessionID = Darwin.getsid(0)
        guard sessionID > 0, sessionID != ownSessionID else { return nil }

        self.sessionID = sessionID
        self.excludedSessionID = ownSessionID
        self.excludedProcessGroup = Darwin.getpgrp()
    }

    /// Sends a signal to all currently live process groups in the PTY session.
    /// Groups are re-enumerated on every call so jobs created immediately before
    /// shutdown, or reparented after the shell exits, are still included.
    @discardableResult
    public func signalAllProcessGroups(_ signal: Int32) -> [pid_t] {
        let groups = currentProcessGroups()
        for group in groups {
            _ = Darwin.kill(-group, signal)
        }
        return groups
    }

    public func currentProcessGroups() -> [pid_t] {
        var groups = Set<pid_t>()
        for pid in Self.allProcessIDs() {
            guard Darwin.getsid(pid) == sessionID else { continue }
            let group = Darwin.getpgid(pid)
            guard group > 0,
                  group != excludedProcessGroup,
                  Darwin.getsid(pid) != excludedSessionID else {
                continue
            }
            groups.insert(group)
        }
        return groups.sorted()
    }

    public func currentProcessIDs() -> [pid_t] {
        Self.allProcessIDs().filter { Darwin.getsid($0) == sessionID }
    }

    private static func allProcessIDs() -> [pid_t] {
        let estimatedCount = Int(Darwin.proc_listallpids(nil, 0))
        guard estimatedCount > 0 else { return [] }

        var capacity = estimatedCount + 64
        for _ in 0..<3 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let copiedCount = pids.withUnsafeMutableBytes { buffer in
                Darwin.proc_listallpids(buffer.baseAddress, Int32(buffer.count))
            }
            guard copiedCount >= 0 else { return [] }
            if copiedCount < capacity {
                return Array(pids.prefix(Int(copiedCount))).filter { $0 > 0 }
            }
            capacity *= 2
        }
        return []
    }
}
