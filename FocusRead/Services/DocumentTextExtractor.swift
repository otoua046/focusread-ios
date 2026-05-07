import Foundation

typealias DocumentImportProgressHandler = @Sendable (DocumentImportProgress) async -> Void

protocol DocumentTextExtractor: Sendable {
    func extractText(
        from file: ImportedFile,
        progress: @escaping DocumentImportProgressHandler
    ) async throws -> ImportedDocument
}

extension String {
    var focusReadNormalizedDocumentText: String {
        let normalizedNewlines = replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalizedNewlines.components(separatedBy: "\n")
        var output: [String] = []
        var previousLineWasBlank = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if !previousLineWasBlank, !output.isEmpty {
                    output.append("")
                }
                previousLineWasBlank = true
            } else {
                output.append(trimmed)
                previousLineWasBlank = false
            }
        }

        return output.joined(separator: "\n")
    }

    var focusReadDecodedHTMLEntities: String {
        let namedEntities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&rsquo;": "’",
            "&lsquo;": "‘",
            "&rdquo;": "”",
            "&ldquo;": "“",
            "&eacute;": "é",
            "&egrave;": "è",
            "&ecirc;": "ê",
            "&agrave;": "à",
            "&ccedil;": "ç",
            "&oelig;": "œ"
        ]

        var decoded = self
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        decoded = decoded.replacingNumericHTMLEntities(pattern: #"&#(\d+);"#, radix: 10)
        decoded = decoded.replacingNumericHTMLEntities(pattern: #"&#x([0-9a-fA-F]+);"#, radix: 16)
        return decoded
    }

    var focusReadRemovingControlCharacters: String {
        String(unicodeScalars.map { scalar in
            if scalar.properties.generalCategory == .control ||
                scalar.value == 0x200B ||
                scalar.value == 0x200C ||
                scalar.value == 0x200D ||
                scalar.value == 0x200E ||
                scalar.value == 0x200F ||
                scalar.value == 0x2028 ||
                scalar.value == 0x2029 ||
                scalar.value == 0x2060 ||
                scalar.value == 0xFEFF {
                return " "
            }

            return String(scalar)
        }.joined())
    }

    private func replacingNumericHTMLEntities(pattern: String, radix: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }

        let nsRange = NSRange(startIndex..<endIndex, in: self)
        var output = self
        for match in regex.matches(in: self, range: nsRange).reversed() {
            guard match.numberOfRanges == 2,
                  let entityRange = Range(match.range(at: 0), in: self),
                  let valueRange = Range(match.range(at: 1), in: self),
                  let value = UInt32(String(self[valueRange]), radix: radix),
                  let scalar = UnicodeScalar(value) else {
                continue
            }

            output.replaceSubrange(entityRange, with: String(scalar))
        }

        return output
    }
}
