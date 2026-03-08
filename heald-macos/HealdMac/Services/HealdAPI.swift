import Foundation

actor HealdAPI {
    static let shared = HealdAPI()

    private var baseURL: String {
        UserDefaults.standard.string(forKey: "heald_api_url") ?? "https://heald.merados.com"
    }

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "heald_api_key") ?? ""
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func fetchMachines() async throws -> [MachineWithHistory] {
        let data = try await request(path: "/api/machines")
        let response = try decoder.decode(MachinesResponse.self, from: data)
        return response.machines
    }

    func fetchEvents(machineId: String? = nil, limit: Int = 100) async throws -> [ActivityEvent] {
        var path = "/api/events?limit=\(limit)"
        if let machineId { path += "&machineId=\(machineId)" }
        let data = try await request(path: path)
        let response = try decoder.decode(EventsResponse.self, from: data)
        return response.events
    }

    private func request(path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw HealdAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw HealdAPIError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw HealdAPIError.unauthorized
        case 404: throw HealdAPIError.notFound
        default: throw HealdAPIError.serverError(http.statusCode)
        }
    }
}

private struct MachinesResponse: Codable { let machines: [MachineWithHistory] }
private struct EventsResponse: Codable { let events: [ActivityEvent] }

enum HealdAPIError: LocalizedError {
    case invalidURL, invalidResponse, unauthorized, notFound, serverError(Int)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response"
        case .unauthorized: return "Invalid API key"
        case .notFound: return "Not found"
        case .serverError(let code): return "Server error (\(code))"
        }
    }
}
