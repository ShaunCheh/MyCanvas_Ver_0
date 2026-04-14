import Foundation

enum CanvasHTTPSURLPolicyError: LocalizedError, Equatable {
    case emptyInput
    case invalidURL
    case missingHost
    case httpSchemeNotAllowed
    case unsupportedScheme(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Enter a website URL."
        case .invalidURL:
            return "The website URL is invalid."
        case .missingHost:
            return "The website URL must include a host."
        case .httpSchemeNotAllowed:
            return "Only HTTPS URLs are supported."
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme). Only HTTPS URLs are supported."
        }
    }
}

// Shared HTTPS normalization keeps future iOS/macOS web editors consistent.
enum CanvasHTTPSURLPolicy {
    static func url(from rawInput: String) throws -> URL {
        let trimmedInput = rawInput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmedInput.isEmpty == false else {
            throw CanvasHTTPSURLPolicyError.emptyInput
        }

        let candidateURLString = resolvedCandidateURLString(
            from: trimmedInput
        )
        guard var components = URLComponents(
            string: candidateURLString
        ) else {
            throw CanvasHTTPSURLPolicyError.invalidURL
        }

        guard let scheme = components.scheme?.lowercased() else {
            throw CanvasHTTPSURLPolicyError.invalidURL
        }
        guard scheme == "https" else {
            if scheme == "http" {
                throw CanvasHTTPSURLPolicyError.httpSchemeNotAllowed
            }
            throw CanvasHTTPSURLPolicyError.unsupportedScheme(scheme)
        }

        guard let host = components.host?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), host.isEmpty == false
        else {
            throw CanvasHTTPSURLPolicyError.missingHost
        }

        components.scheme = "https"
        components.host = host.lowercased()
        guard let resolvedURL = components.url else {
            throw CanvasHTTPSURLPolicyError.invalidURL
        }
        return resolvedURL
    }

    static func normalizedString(from rawInput: String) throws -> String {
        try url(from: rawInput).absoluteString
    }

    private static func resolvedCandidateURLString(
        from trimmedInput: String
    ) -> String {
        if trimmedInput.hasPrefix("//") {
            return "https:" + trimmedInput
        }

        guard hasExplicitSchemePrefix(trimmedInput) == false else {
            return trimmedInput
        }

        return "https://" + trimmedInput
    }

    private static func hasExplicitSchemePrefix(_ input: String) -> Bool {
        guard let schemeSeparatorRange = input.range(of: "://") else {
            return false
        }

        let schemeCandidate = input[..<schemeSeparatorRange.lowerBound]
        guard let firstCharacter = schemeCandidate.first else {
            return false
        }
        guard firstCharacter.isLetter else {
            return false
        }

        return schemeCandidate.dropFirst().allSatisfy { character in
            character.isLetter ||
                character.isNumber ||
                character == "+" ||
                character == "." ||
                character == "-"
        }
    }
}
