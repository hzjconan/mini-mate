import Foundation

/// Driver-agnostic secret redaction utility (RS-1, Constitution VII).
/// Scrubs registered plaintext secrets, bearer tokens, sk- tokens, and common sensitive JSON fields.
public enum SecretRedactor {
    private static let placeholder = "[REDACTED]"

    private static let bearerRegex = try! NSRegularExpression(
        pattern: #"Bearer\s+[A-Za-z0-9._\-]+"#,
        options: [.caseInsensitive]
    )

    private static let skTokenRegex = try! NSRegularExpression(
        pattern: #"sk-[A-Za-z0-9_\-]{8,}"#,
        options: []
    )

    private static let sensitiveJSONFieldRegex = try! NSRegularExpression(
        pattern: #""(authorization|x-api-key|x-api-access-key|x-api-app-id|x-api-app-key|api_key|access_key|secret|token)"\s*:\s*"[^"]*""#,
        options: [.caseInsensitive]
    )

    public static func redact(_ text: String, secrets: [String] = []) -> String {
        var result = text

        // Replace registered plaintext secrets (longest first to avoid partial match artifacts).
        let filteredSecrets = Array(Set(secrets.filter { $0.count >= 4 }))
            .sorted { $0.count > $1.count }
        for secret in filteredSecrets {
            result = result.replacingOccurrences(of: secret, with: placeholder)
        }

        result = replaceMatches(
            in: result,
            regex: bearerRegex,
            template: "Bearer \(placeholder)"
        )
        result = replaceMatches(
            in: result,
            regex: skTokenRegex,
            template: placeholder
        )
        result = replaceMatches(
            in: result,
            regex: sensitiveJSONFieldRegex,
            template: "\"$1\":\"\(placeholder)\""
        )

        return result
    }

    public static func sanitizedErrorMessage(_ error: any Error, secrets: [String] = []) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return redact(raw, secrets: secrets)
    }

    private static func replaceMatches(
        in text: String,
        regex: NSRegularExpression,
        template: String
    ) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
