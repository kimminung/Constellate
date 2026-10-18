import ConstellateKit
import Foundation
import SwiftUI

/// Tiny regex-free tokenizer good enough for previews: keywords / types / functions / strings / numbers / comments.
nonisolated enum SyntaxHighlighter {

    enum TokenKind: Sendable {
        case plain, keyword, type, function, string, number, comment
    }

    struct Token: Sendable {
        var text: Substring
        var kind: TokenKind
    }

    static let keywords: Set<String> = [
        "import", "struct", "class", "enum", "protocol", "extension", "actor", "func", "var", "let", "init", "deinit",
        "return", "if", "else", "guard", "for", "in", "while", "repeat", "switch", "case", "default", "break", "continue",
        "where", "do", "try", "catch", "throw", "throws", "rethrows", "async", "await", "some", "any", "self", "Self",
        "super", "static", "final", "private", "fileprivate", "internal", "public", "open", "override", "mutating",
        "nonisolated", "isolated", "inout", "typealias", "associatedtype", "subscript", "defer", "is", "as", "nil",
        "true", "false", "weak", "unowned", "lazy", "indirect", "convenience", "required", "operator", "precedencegroup",
        "def", "fn", "const", "void", "int", "float", "double", "bool", "string", "new", "this", "null", "None", "elif",
        "pass", "lambda", "yield", "from", "with", "not", "and", "or", "package", "interface", "implements", "export"
    ]

    static func tokenize(line: Substring) -> [Token] {
        var tokens: [Token] = []
        var i = line.startIndex
        let end = line.endIndex

        func flushPlain(_ start: String.Index, _ stop: String.Index) {
            if start < stop { tokens.append(Token(text: line[start..<stop], kind: .plain)) }
        }

        while i < end {
            let c = line[i]
            // Comments: // or #
            if c == "/" , line.index(after: i) < end, line[line.index(after: i)] == "/" {
                tokens.append(Token(text: line[i..<end], kind: .comment))
                return tokens
            }
            if c == "#" && (i == line.startIndex || line[line.index(before: i)].isWhitespace) {
                // Swift `#if` is a keyword-ish directive; Python `#` is a comment. Treat `#if/#else/#endif/#available` as keyword.
                let rest = line[i..<end]
                if rest.hasPrefix("#if") || rest.hasPrefix("#else") || rest.hasPrefix("#endif") || rest.hasPrefix("#available") || rest.hasPrefix("#Preview") {
                    let wordEnd = rest.firstIndex(where: { $0.isWhitespace || $0 == "(" }) ?? end
                    tokens.append(Token(text: line[i..<wordEnd], kind: .keyword))
                    i = wordEnd
                    continue
                }
                tokens.append(Token(text: rest, kind: .comment))
                return tokens
            }
            // Strings
            if c == "\"" {
                var j = line.index(after: i)
                while j < end {
                    if line[j] == "\\" { j = line.index(j, offsetBy: 2, limitedBy: end) ?? end; continue }
                    if line[j] == "\"" { j = line.index(after: j); break }
                    j = line.index(after: j)
                }
                tokens.append(Token(text: line[i..<j], kind: .string))
                i = j
                continue
            }
            // Numbers
            if c.isNumber {
                var j = i
                while j < end, line[j].isNumber || line[j] == "." || line[j] == "_" || line[j] == "x" || line[j].isHexDigit { j = line.index(after: j) }
                tokens.append(Token(text: line[i..<j], kind: .number))
                i = j
                continue
            }
            // Identifiers / keywords / attributes
            if c.isLetter || c == "_" || c == "@" {
                var j = line.index(after: i)
                while j < end, line[j].isLetter || line[j].isNumber || line[j] == "_" { j = line.index(after: j) }
                let word = line[i..<j]
                let kind: TokenKind
                if word.hasPrefix("@") || keywords.contains(String(word)) {
                    kind = .keyword
                } else if let first = word.first, first.isUppercase {
                    kind = .type
                } else if j < end, line[j] == "(" {
                    kind = .function
                } else {
                    kind = .plain
                }
                tokens.append(Token(text: word, kind: kind))
                i = j
                continue
            }
            // Anything else: accumulate one char as plain
            let next = line.index(after: i)
            flushPlain(i, next)
            i = next
        }
        return tokens
    }

    static func color(for kind: TokenKind, palette: CodePalette) -> RGBA {
        switch kind {
        case .plain: palette.plain
        case .keyword: palette.keyword
        case .type: palette.type
        case .function: palette.function
        case .string: palette.string
        case .number: palette.number
        case .comment: palette.comment
        }
    }

    /// Full AttributedString for SwiftUI `Text`.
    static func attributed(_ source: String, palette: CodePalette, font: Font = .system(.callout, design: .monospaced)) -> AttributedString {
        var result = AttributedString()
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, line) in lines.enumerated() {
            for token in tokenize(line: line) {
                var piece = AttributedString(String(token.text))
                piece.foregroundColor = color(for: token.kind, palette: palette).swiftUIColor
                piece.font = font
                result.append(piece)
            }
            if index < lines.count - 1 { result.append(AttributedString("\n")) }
        }
        return result
    }
}
