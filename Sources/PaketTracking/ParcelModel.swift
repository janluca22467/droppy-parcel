import Foundation

public enum ParcelCarrier: String, Codable, CaseIterable, Sendable, Identifiable {
    case dhl
    case dpd

    public var id: String { rawValue }
    public var title: String { self == .dhl ? "DHL" : "DPD" }
}

public enum ParcelStatus: String, Codable, Sendable {
    case unknown
    case preTransit
    case inTransit
    case outForDelivery
    case delivered
    case problem

    public var title: String {
        switch self {
        case .unknown: return "Unbekannt"
        case .preTransit: return "Angekündigt"
        case .inTransit: return "Unterwegs"
        case .outForDelivery: return "In Zustellung"
        case .delivered: return "Zugestellt"
        case .problem: return "Problem"
        }
    }
}

public struct ParcelUpdate: Sendable, Equatable {
    public var status: ParcelStatus
    public var detail: String?
    public var eta: Date?
}

public struct Parcel: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var carrier: ParcelCarrier
    public var number: String
    public var label: String
    public var status: ParcelStatus
    public var detail: String?
    public var eta: Date?
    public var checkedAt: Date?
    public var deliveredAt: Date?
    public var error: String?

    public init(carrier: ParcelCarrier, number: String, label: String) {
        self.id = UUID().uuidString
        self.carrier = carrier
        self.number = number
        self.label = label
        self.status = .unknown
    }

    public var displayName: String { label.isEmpty ? number : label }

    public func arrivesToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard status != .delivered, status != .problem else { return false }
        if status == .outForDelivery { return true }
        guard let eta else { return false }
        return calendar.isDate(eta, inSameDayAs: now)
    }

    func sortRank(now: Date) -> Int {
        if arrivesToday(now: now) { return 0 }
        switch status {
        case .inTransit, .preTransit: return 1
        case .problem, .unknown: return 2
        case .outForDelivery: return 0
        case .delivered: return 3
        }
    }
}

public enum ParcelTrackingError: Error, LocalizedError, Sendable {
    case missingKey
    case invalidKey
    case notFound
    case rateLimited
    case http(Int)
    case unreadable
    case offline(Int)
    case timedOut
    case blocked(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey: return "DHL-API-Schlüssel fehlt"
        case .invalidKey: return "DHL-API-Schlüssel ungültig"
        case .notFound: return "Sendung nicht gefunden"
        case .rateLimited: return "Zu viele Abfragen"
        case .http(let code): return "Serverfehler \(code)"
        case .unreadable: return "Antwort nicht lesbar"
        case .offline(let code): return code == -1005 ? "Server hat die Verbindung getrennt (-1005)" : "Keine Internetverbindung (\(code))"
        case .timedOut: return "Zeitüberschreitung"
        case .blocked(let detail): return "Verbindung fehlgeschlagen (\(detail))"
        }
    }
}

public enum ParcelParser {
    public static func parseDHL(_ data: Data) throws -> ParcelUpdate {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shipment = (root["shipments"] as? [[String: Any]])?.first
        else { throw ParcelTrackingError.notFound }

        let statusObject = shipment["status"] as? [String: Any]
        let code = (statusObject?["statusCode"] as? String)?.lowercased() ?? ""
        let events = (shipment["events"] as? [[String: Any]]) ?? []
        let latestText = [statusObject, events.first].compactMap { $0 }
            .flatMap { [$0["status"], $0["description"], $0["remark"]] }
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .lowercased()

        var status: ParcelStatus
        switch code {
        case "pre-transit": status = .preTransit
        case "transit": status = .inTransit
        case "delivered": status = .delivered
        case "failure": status = .problem
        default: status = .unknown
        }
        if status == .inTransit || status == .unknown,
           ["zustellfahrzeug", "in zustellung", "out for delivery", "delivery vehicle", "wird zugestellt"]
            .contains(where: latestText.contains) {
            status = .outForDelivery
        }

        let detail = (statusObject?["description"] as? String)
            ?? (statusObject?["status"] as? String)
            ?? (events.first?["description"] as? String)

        var eta = parseDate(shipment["estimatedTimeOfDelivery"] as? String)
        if eta == nil, let range = shipment["estimatedTimeOfDeliveryRemark"] as? String { eta = parseDate(range) }
        return ParcelUpdate(status: status, detail: detail, eta: eta)
    }

    public static func parseDPD(_ data: Data) throws -> ParcelUpdate {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw ParcelTrackingError.unreadable }
        guard let steps = findSteps(in: root), !steps.isEmpty else {
            if let dictionary = root as? [String: Any], dictionary["errors"] != nil || dictionary["error"] != nil {
                throw ParcelTrackingError.notFound
            }
            throw ParcelTrackingError.unreadable
        }

        let current = steps.first { ($0["isCurrentStatus"] as? Bool) == true }
            ?? steps.last { ($0["statusHasBeenReached"] as? Bool) == true }
        guard let current, let raw = current["status"] as? String else { throw ParcelTrackingError.unreadable }

        let status: ParcelStatus
        switch raw.uppercased() {
        case "ACCEPTED", "PICKED_UP", "AT_SEND_DEPOT": status = .preTransit
        case "ON_THE_ROAD", "AT_DELIVERY_DEPOT", "IN_TRANSIT": status = .inTransit
        case "DELIVERY", "OUT_FOR_DELIVERY": status = .outForDelivery
        case "DELIVERED": status = .delivered
        case "PICKUP", "PICKUP_READY", "NOT_DELIVERED", "RETURNED", "EXCEPTION": status = .problem
        default: status = .unknown
        }

        let description = ((current["description"] as? [String: Any])?["content"] as? [String])?.first
        let detail = description ?? (current["label"] as? String)
        return ParcelUpdate(status: status, detail: detail, eta: nil)
    }

    static func findSteps(in node: Any) -> [[String: Any]]? {
        if let dictionary = node as? [String: Any] {
            if let steps = dictionary["statusInfo"] as? [[String: Any]] { return steps }
            for value in dictionary.values {
                if let found = findSteps(in: value) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findSteps(in: value) { return found }
            }
        }
        return nil
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: string) { return date }
        }
        return nil
    }
}

public enum ParcelClient {
    public static func fetch(_ parcel: Parcel, dhlKey: String) async throws -> ParcelUpdate {
        let number = parcel.number.trimmingCharacters(in: .whitespacesAndNewlines)
        switch parcel.carrier {
        case .dhl:
            guard !dhlKey.isEmpty else { throw ParcelTrackingError.missingKey }
            var components = URLComponents(string: "https://api-eu.dhl.com/track/shipments")!
            components.queryItems = [
                URLQueryItem(name: "trackingNumber", value: number),
                URLQueryItem(name: "language", value: "de")
            ]
            var request = URLRequest(url: components.url!, timeoutInterval: 20)
            request.setValue(dhlKey, forHTTPHeaderField: "DHL-API-Key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return try ParcelParser.parseDHL(try await load(request, keyed: true))
        case .dpd:
            let digits = number.filter(\.isNumber)
            let candidates = digits.count > 14 ? [String(digits.prefix(14)), digits] : [digits]
            var lastError: Error = ParcelTrackingError.notFound
            for candidate in candidates where !candidate.isEmpty {
                guard let url = URL(string: "https://tracking.dpd.de/rest/plc/de_DE/\(candidate)") else { continue }
                var request = URLRequest(url: url, timeoutInterval: 20)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("de-DE", forHTTPHeaderField: "Accept-Language")
                request.setValue("https://tracking.dpd.de/", forHTTPHeaderField: "Referer")
                do {
                    return try ParcelParser.parseDPD(try await load(request))
                } catch ParcelTrackingError.notFound {
                    lastError = ParcelTrackingError.notFound
                } catch {
                    throw error
                }
            }
            throw lastError
        }
    }

    private static func load(_ request: URLRequest, keyed: Bool = false) async throws -> Data {
        let data: Data
        let response: URLResponse
        var request = request
        request.setValue("PaketTracking/1.0 (Droppy droplet)", forHTTPHeaderField: "User-Agent")
        do {
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError where error.code == .networkConnectionLost {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                (data, response) = try await URLSession.shared.data(for: request)
            }
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost: throw ParcelTrackingError.offline(error.code.rawValue)
            case .timedOut: throw ParcelTrackingError.timedOut
            default: throw ParcelTrackingError.blocked("\(error.code.rawValue) \(error.localizedDescription)")
            }
        }
        guard let http = response as? HTTPURLResponse else { throw ParcelTrackingError.unreadable }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw keyed ? ParcelTrackingError.invalidKey : ParcelTrackingError.http(http.statusCode)
        case 404: throw ParcelTrackingError.notFound
        case 429: throw ParcelTrackingError.rateLimited
        default: throw ParcelTrackingError.http(http.statusCode)
        }
    }
}
