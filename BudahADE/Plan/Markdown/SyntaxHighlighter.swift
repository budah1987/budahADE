import SwiftUI

// MARK: - Token Types

enum SyntaxTokenType {
    case keyword
    case type
    case string
    case number
    case comment
    case plain
}

struct SyntaxToken {
    let text: String
    let type: SyntaxTokenType
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {

    static func tokenize(_ code: String, language: String?) -> [SyntaxToken] {
        let lang = language?.lowercased() ?? ""
        let rules = languageRules(for: lang)
        return applyRules(to: code, rules: rules)
    }

    static func highlight(_ code: String, language: String?) -> AttributedString {
        let tokens = tokenize(code, language: language)
        var result = AttributedString()
        for token in tokens {
            var segment = AttributedString(token.text)
            segment.foregroundColor = color(for: token.type)
            result.append(segment)
        }
        return result
    }

    // MARK: - Colors

    private static func color(for type: SyntaxTokenType) -> Color {
        switch type {
        case .keyword: return Theme.accent
        case .type:    return Theme.info
        case .string:  return Theme.success
        case .number:  return Theme.warning
        case .comment: return Theme.textMuted
        case .plain:   return Theme.textPrimary
        }
    }

    // MARK: - Language Rules

    private struct HighlightRule {
        let pattern: String
        let type: SyntaxTokenType
        let options: NSRegularExpression.Options

        init(_ pattern: String, _ type: SyntaxTokenType, options: NSRegularExpression.Options = []) {
            self.pattern = pattern
            self.type = type
            self.options = options
        }
    }

    private static func languageRules(for language: String) -> [HighlightRule] {
        var rules: [HighlightRule] = []

        // Comments first (highest priority)
        switch language {
        case "python", "bash", "sh", "zsh", "shell":
            rules.append(HighlightRule(#"#[^\n]*"#, .comment))
        case "html", "xml":
            rules.append(HighlightRule(#"<!--[\s\S]*?-->"#, .comment, options: .dotMatchesLineSeparators))
        case "css":
            rules.append(HighlightRule(#"/\*[\s\S]*?\*/"#, .comment, options: .dotMatchesLineSeparators))
        case "sql":
            rules.append(HighlightRule(#"--[^\n]*"#, .comment))
            rules.append(HighlightRule(#"/\*[\s\S]*?\*/"#, .comment, options: .dotMatchesLineSeparators))
        default:
            rules.append(HighlightRule(#"/\*[\s\S]*?\*/"#, .comment, options: .dotMatchesLineSeparators))
            rules.append(HighlightRule(#"//[^\n]*"#, .comment))
        }

        // Strings
        rules.append(HighlightRule(#""""[\s\S]*?""""#, .string, options: .dotMatchesLineSeparators))
        rules.append(HighlightRule(#""(?:[^"\\]|\\.)*""#, .string))
        rules.append(HighlightRule(#"'(?:[^'\\]|\\.)*'"#, .string))
        rules.append(HighlightRule(#"`(?:[^`\\]|\\.)*`"#, .string))

        // Numbers
        rules.append(HighlightRule(#"\b0x[0-9a-fA-F]+\b"#, .number))
        rules.append(HighlightRule(#"\b\d+\.?\d*\b"#, .number))

        // Keywords
        let keywords = keywordsForLanguage(language)
        if !keywords.isEmpty {
            let pattern = #"\b(?:"# + keywords.joined(separator: "|") + #")\b"#
            rules.append(HighlightRule(pattern, .keyword))
        }

        // Type identifiers (PascalCase)
        rules.append(HighlightRule(#"\b[A-Z][a-zA-Z0-9]+\b"#, .type))

        return rules
    }

    private static func keywordsForLanguage(_ language: String) -> [String] {
        switch language {
        case "swift":
            return ["import", "func", "var", "let", "class", "struct", "enum", "protocol",
                    "extension", "return", "if", "else", "guard", "switch", "case", "default",
                    "for", "while", "repeat", "break", "continue", "throw", "throws", "try",
                    "catch", "do", "in", "as", "is", "self", "Self", "super", "init", "deinit",
                    "nil", "true", "false", "static", "private", "public", "internal", "open",
                    "fileprivate", "override", "mutating", "nonmutating", "some", "any",
                    "async", "await", "actor", "nonisolated", "weak", "unowned", "lazy",
                    "where", "typealias", "associatedtype", "inout", "convenience", "required",
                    "final", "dynamic", "optional", "indirect", "precedencegroup", "operator"]
        case "python":
            return ["def", "class", "import", "from", "return", "if", "elif", "else",
                    "for", "while", "break", "continue", "try", "except", "finally",
                    "raise", "with", "as", "pass", "yield", "lambda", "and", "or", "not",
                    "in", "is", "None", "True", "False", "global", "nonlocal", "del",
                    "assert", "async", "await", "self"]
        case "javascript", "typescript", "js", "ts", "jsx", "tsx":
            return ["const", "let", "var", "function", "return", "if", "else", "for",
                    "while", "do", "switch", "case", "default", "break", "continue",
                    "try", "catch", "finally", "throw", "new", "delete", "typeof",
                    "instanceof", "in", "of", "class", "extends", "super", "this",
                    "import", "export", "from", "as", "async", "await", "yield",
                    "null", "undefined", "true", "false", "void", "static", "get", "set",
                    "interface", "type", "enum", "implements", "abstract", "readonly"]
        case "rust":
            return ["fn", "let", "mut", "const", "static", "struct", "enum", "trait",
                    "impl", "mod", "use", "pub", "crate", "super", "self", "Self",
                    "if", "else", "match", "for", "while", "loop", "break", "continue",
                    "return", "as", "in", "ref", "move", "async", "await", "dyn",
                    "where", "type", "unsafe", "extern", "true", "false"]
        case "go", "golang":
            return ["func", "var", "const", "type", "struct", "interface", "map",
                    "chan", "package", "import", "return", "if", "else", "for",
                    "range", "switch", "case", "default", "break", "continue",
                    "go", "defer", "select", "fallthrough", "nil", "true", "false"]
        case "bash", "sh", "zsh", "shell":
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                    "case", "esac", "in", "function", "return", "exit", "local",
                    "export", "source", "echo", "read", "set", "unset", "shift",
                    "true", "false"]
        case "sql":
            return ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE",
                    "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX",
                    "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AND", "OR",
                    "NOT", "NULL", "IS", "IN", "AS", "ORDER", "BY", "GROUP", "HAVING",
                    "LIMIT", "OFFSET", "DISTINCT", "COUNT", "SUM", "AVG", "MAX", "MIN",
                    "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "CASCADE", "CONSTRAINT",
                    "select", "from", "where", "insert", "into", "values", "update",
                    "set", "delete", "create", "table", "alter", "drop", "join",
                    "left", "right", "inner", "outer", "on", "and", "or", "not",
                    "null", "is", "in", "as", "order", "by", "group", "having",
                    "limit", "offset", "distinct"]
        case "json":
            return ["true", "false", "null"]
        case "yaml", "yml":
            return ["true", "false", "null", "yes", "no", "on", "off"]
        default:
            return []
        }
    }

    // MARK: - Rule Application

    private static func applyRules(to code: String, rules: [HighlightRule]) -> [SyntaxToken] {
        var typeMap = Array(repeating: SyntaxTokenType.plain, count: code.utf16.count)

        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { continue }
            let nsRange = NSRange(code.startIndex..<code.endIndex, in: code)
            let matches = regex.matches(in: code, range: nsRange)
            for match in matches {
                guard let range = Range(match.range, in: code) else { continue }
                let utf16Start = code.utf16.distance(from: code.utf16.startIndex, to: range.lowerBound.samePosition(in: code.utf16) ?? code.utf16.startIndex)
                let utf16End = code.utf16.distance(from: code.utf16.startIndex, to: range.upperBound.samePosition(in: code.utf16) ?? code.utf16.endIndex)
                for i in utf16Start..<min(utf16End, typeMap.count) {
                    if typeMap[i] == .plain { typeMap[i] = rule.type }
                }
            }
        }

        var tokens: [SyntaxToken] = []
        var currentType: SyntaxTokenType = typeMap.isEmpty ? .plain : typeMap[0]
        var currentChars: [Character] = []
        var utf16Index = 0

        for char in code {
            let charUTF16Count = String(char).utf16.count
            let charType = utf16Index < typeMap.count ? typeMap[utf16Index] : .plain
            if charType == currentType {
                currentChars.append(char)
            } else {
                if !currentChars.isEmpty {
                    tokens.append(SyntaxToken(text: String(currentChars), type: currentType))
                }
                currentChars = [char]
                currentType = charType
            }
            utf16Index += charUTF16Count
        }
        if !currentChars.isEmpty {
            tokens.append(SyntaxToken(text: String(currentChars), type: currentType))
        }
        return tokens
    }
}
