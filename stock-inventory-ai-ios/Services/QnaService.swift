//
//  QnaService.swift
//  stock-inventory-ai-ios
//

import Foundation

struct QnaRequest: Encodable {
    let question: String
}

struct QnaResponse: Decodable {
    let answer: String
}

enum QnaServiceError: LocalizedError {
    case invalidResponse
    case server(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from server."
        case .server(let status):
            return "Server returned an error (status \(status))."
        }
    }
}

protocol QnaServicing {
    func ask(question: String) async throws -> String
}

final class QnaService: QnaServicing {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func ask(question: String) async throws -> String {
        let url = baseURL.appendingPathComponent("qna")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(QnaRequest(question: question))

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QnaServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw QnaServiceError.server(status: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(QnaResponse.self, from: data).answer
    }
}
