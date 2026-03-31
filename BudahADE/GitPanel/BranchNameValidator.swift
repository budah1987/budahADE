// BudahADE/GitPanel/BranchNameValidator.swift
import Foundation

enum BranchNameValidator {

    struct PrefixType: Identifiable {
        let id: String
        let prefix: String
        let label: String
        var color: String

        init(prefix: String, label: String, color: String) {
            self.id = prefix
            self.prefix = prefix
            self.label = label
            self.color = color
        }
    }

    static let prefixTypes: [PrefixType] = [
        PrefixType(prefix: "feat",       label: "feature",     color: "success"),
        PrefixType(prefix: "fix",        label: "bug fix",     color: "error"),
        PrefixType(prefix: "ui",         label: "visual",      color: "accent"),
        PrefixType(prefix: "refactor",   label: "restructure", color: "info"),
        PrefixType(prefix: "chore",      label: "maintenance", color: "textMuted"),
        PrefixType(prefix: "docs",       label: "specs",       color: "info"),
        PrefixType(prefix: "experiment", label: "prototype",   color: "warning"),
    ]

    private static let invalidChars = CharacterSet(charactersIn: "~^:?*[\\")
    private static let knownPrefixes = Set(prefixTypes.map(\.prefix))

    static func sanitize(_ input: String) -> String {
        var result = input
        result = result.unicodeScalars.filter { $0.value >= 32 }.map(String.init).joined()
        result = result.replacingOccurrences(of: " ", with: "-")
        result = result.unicodeScalars.filter { !invalidChars.contains($0) }.map(String.init).joined()
        while result.contains("//") { result = result.replacingOccurrences(of: "//", with: "/") }
        while result.contains("..") { result = result.replacingOccurrences(of: "..", with: ".") }
        let trimChars = CharacterSet(charactersIn: "/.")
        result = result.trimmingCharacters(in: trimChars)
        if result.hasSuffix(".lock") {
            result = String(result.dropLast(5))
        }
        return result
    }

    static func detectPrefix(_ branchName: String) -> String? {
        guard let slashIndex = branchName.firstIndex(of: "/") else { return nil }
        let candidate = String(branchName[branchName.startIndex..<slashIndex])
        return knownPrefixes.contains(candidate) ? candidate : nil
    }

    static func split(_ branchName: String) -> (prefix: String?, name: String) {
        guard let detected = detectPrefix(branchName),
              let slashIndex = branchName.firstIndex(of: "/") else {
            return (nil, branchName)
        }
        let name = String(branchName[branchName.index(after: slashIndex)...])
        return (detected, name)
    }

    static func compose(prefix: String?, name: String) -> String {
        if let prefix, !prefix.isEmpty {
            return "\(prefix)/\(name)"
        }
        return name
    }
}
