import Foundation

struct DictationResult: Decodable, Equatable {
    let text: String
    let raw: String
}

enum DictationError: Error, Equatable {
    case unauthorized
    case limitReached
    case tooLong
    case offline
    case badAddress
    case failed

    /// Plain-language message shown to the person.
    var message: String {
        switch self {
        case .unauthorized: return "Token not accepted, check setup"
        case .limitReached: return "Monthly limit reached"
        case .tooLong: return "Recording too long"
        case .offline: return "No internet"
        case .badAddress: return "Worker address looks wrong, check setup"
        case .failed: return "Didn't work, try again"
        }
    }
}

/// Sends one recording to the Worker and returns the cleaned-up text.
struct DictationClient {
    var session: URLSession = .shared

    /// Turns what the person typed in setup into the `/dictate` URL.
    /// Accepts the address with or without `https://` and with or without a trailing slash.
    static func endpoint(from address: String) -> URL? {
        var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("https://") && !trimmed.lowercased().hasPrefix("http://") {
            trimmed = "https://" + trimmed
        }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.lowercased().hasSuffix("/dictate") { trimmed.removeLast("/dictate".count) }
        guard let url = URL(string: trimmed), let host = url.host, !host.isEmpty else { return nil }
        return url.appendingPathComponent("dictate")
    }

    func dictate(audio: Data, seconds: Int, address: String, token: String) async throws -> DictationResult {
        guard let url = Self.endpoint(from: address) else { throw DictationError.badAddress }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue(String(max(seconds, 1)), forHTTPHeaderField: "X-Duration-Seconds")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: audio)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw DictationError.offline
            default:
                throw DictationError.failed
            }
        } catch {
            throw DictationError.failed
        }

        guard let http = response as? HTTPURLResponse else { throw DictationError.failed }
        switch http.statusCode {
        case 200:
            guard let result = try? JSONDecoder().decode(DictationResult.self, from: data) else {
                throw DictationError.failed
            }
            return result
        case 401: throw DictationError.unauthorized
        case 413: throw DictationError.tooLong
        case 429: throw DictationError.limitReached
        default: throw DictationError.failed
        }
    }
}
