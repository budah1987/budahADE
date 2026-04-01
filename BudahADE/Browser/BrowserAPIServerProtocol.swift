import Foundation

/// Protocol for the browser REST API HTTP server.
/// Separates the interface from the NWListener implementation so it can be
/// swapped for testing or a different HTTP backend later.
protocol BrowserAPIServerProtocol: AnyObject {
    /// Start listening on the given port. Throws if the port is unavailable.
    func start(port: UInt16) throws
    /// Stop listening and close all active connections.
    func stop()
    /// Register a task's BrowserState so requests routed by X-Task-Id can reach it.
    func registerTask(id: UUID, state: BrowserState)
    /// Remove a task from the registry when its browser tab is closed.
    func unregisterTask(id: UUID)
}
