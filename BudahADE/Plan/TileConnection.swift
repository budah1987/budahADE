import Foundation

// MARK: - TileConnection

struct TileConnection: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceId: UUID
    let destinationId: UUID
    var cachedSummary: String?
    var summaryTimestamp: Date?
    var sourceVersion: Int

    init(
        id: UUID = UUID(),
        sourceId: UUID,
        destinationId: UUID,
        cachedSummary: String? = nil,
        summaryTimestamp: Date? = nil,
        sourceVersion: Int
    ) {
        self.id = id
        self.sourceId = sourceId
        self.destinationId = destinationId
        self.cachedSummary = cachedSummary
        self.summaryTimestamp = summaryTimestamp
        self.sourceVersion = sourceVersion
    }
}

// MARK: - TileOutput

enum TileOutput {
    case text(String)
    case conversation([ChatMessage])
    case image(URL)
    case url(URL)
    case terminalOutput(String)

    var textRepresentation: String {
        switch self {
        case .text(let s):
            return s

        case .terminalOutput(let s):
            return s

        case .image(let url):
            return "[Image: \(url.lastPathComponent)]"

        case .url(let url):
            return "[URL: \(url.absoluteString)]"

        case .conversation(let messages):
            let last10 = messages.suffix(10)
            return last10.map { msg in
                let label: String
                switch msg.role {
                case .user:    label = "User"
                case .assistant: label = "Assistant"
                case .system:  label = "System"
                }
                return "\(label): \(msg.content)"
            }.joined(separator: "\n")
        }
    }
}
