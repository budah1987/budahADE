import Foundation

// MARK: - Port Allocator

/// Allocates ports per-project using windowed ranges.
/// Project 1: 3000-3010, Project 2: 3012-3022, etc. (+2 gap between windows).
@MainActor
final class PortAllocator {
    static let shared = PortAllocator()

    private let basePort = 3000
    private let windowSize = 11   // 3000-3010 inclusive
    private let gap = 2           // +2 between windows

    /// projectIndex → set of allocated ports within that window
    private var allocations: [Int: Set<Int>] = [:]

    /// Allocate the next free port for a project.
    func allocate(projectIndex: Int) -> Int? {
        let windowStart = basePort + projectIndex * (windowSize + gap)
        let windowEnd = windowStart + windowSize - 1

        let used = allocations[projectIndex] ?? []
        for port in windowStart...windowEnd {
            if !used.contains(port) && isPortAvailable(port) {
                allocations[projectIndex, default: []].insert(port)
                return port
            }
        }
        return nil  // Window exhausted
    }

    /// Release a port back to the pool.
    func release(port: Int) {
        for (projectIndex, var ports) in allocations {
            if ports.remove(port) != nil {
                allocations[projectIndex] = ports
                return
            }
        }
    }

    /// Release all ports for a project.
    func releaseAll(projectIndex: Int) {
        allocations.removeValue(forKey: projectIndex)
    }

    // MARK: - Port Availability

    /// Check if a port is available by attempting to bind.
    private func isPortAvailable(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian

        var reuseAddr: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout.size(ofValue: reuseAddr)))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
