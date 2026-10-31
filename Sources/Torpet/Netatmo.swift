import Foundation

// Netatmo Weather API: https://dev.netatmo.com/apidocumentation/weather
// getstationsdata ger aktuella värden, getmeasure ger historik.
// Netatmo byter refresh-token vid varje förnyelse, så den nya sparas direkt.

// MARK: - JSON

enum JSONValue: Decodable, Equatable, Sendable {
    case number(Double), string(String), bool(Bool), other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else { self = .other }
    }

    var double: Double? { if case .number(let d) = self { return d }; return nil }
    var string: String? { if case .string(let s) = self { return s }; return nil }
}

private struct StationsResponse: Decodable {
    struct Body: Decodable { let devices: [Device]? }
    struct Place: Decodable { let city: String?; let altitude: Double? }
    struct Device: Decodable {
        let _id: String
        let type: String?
        let station_name: String?
        let home_name: String?
        let module_name: String?
        let place: Place?
        let reachable: Bool?
        let wifi_status: Int?
        let last_status_store: Double?
        let data_type: [String]?
        let dashboard_data: [String: JSONValue]?
        let modules: [Module]?
    }
    struct Module: Decodable {
        let _id: String
        let type: String?
        let module_name: String?
        let reachable: Bool?
        let battery_percent: Int?
        let rf_status: Int?
        let last_seen: Double?
        let data_type: [String]?
        let dashboard_data: [String: JSONValue]?
    }
    let body: Body
}

private struct APIErrorResponse: Decodable {
    struct E: Decodable { let code: Int?; let message: String? }
    let error: E?
}

// MARK: - Modell

struct Station: Sendable {
    let id: String
    let name: String
    let city: String?
    let altitude: Double?
    /// Basstationen (inne) först, sedan modulerna.
    let modules: [Module]

    var indoor: Module? { modules.first { $0.kind == .indoor } }
    var outdoor: Module? { modules.first { $0.kind == .outdoor && $0.reachable } }
}

struct Module: Identifiable, Sendable {
    enum Kind: Sendable { case indoor, outdoor, wind, rain, extraIndoor, unknown }

    let id: String
    let deviceID: String
    let type: String
    let name: String
    let values: [String: JSONValue]
    let dataTypes: [String]
    let battery: Int?
    let rfStatus: Int?
    let wifiStatus: Int?
    let reachable: Bool
    let lastSeen: Date?

    var kind: Kind {
        switch type {
        case "NAMain": .indoor
        case "NAModule1": .outdoor
        case "NAModule2": .wind
        case "NAModule3": .rain
        case "NAModule4": .extraIndoor
        default: .unknown
        }
    }

    func number(_ key: String) -> Double? { values[key]?.double }
    var measuredAt: Date? { number("time_utc").map { Date(timeIntervalSince1970: $0) } }
}

enum Measure: String, CaseIterable, Sendable {
    case temperature, humidity, co2, pressure, noise, rain, wind

    var label: String {
        switch self {
        case .temperature: L.t("Temperatur", "Temperature")
        case .humidity: L.t("Luftfuktighet", "Humidity")
        case .co2: L.t("Koldioxid", "CO₂")
        case .pressure: L.t("Lufttryck", "Pressure")
        case .noise: L.t("Ljud", "Noise")
        case .rain: L.t("Regn", "Rain")
        case .wind: L.t("Vind", "Wind")
        }
    }

    var unit: String {
        switch self {
        case .temperature: "°"
        case .humidity: "%"
        case .co2: "ppm"
        case .pressure: "mbar"
        case .noise: "dB"
        case .rain: "mm"
        case .wind: "m/s"
        }
    }

    static func available(for module: Module) -> [Measure] {
        switch module.kind {
        case .indoor: [.temperature, .humidity, .co2, .pressure, .noise]
        case .outdoor: [.temperature, .humidity]
        case .extraIndoor: [.temperature, .humidity, .co2]
        case .rain: [.rain]
        case .wind: [.wind]
        case .unknown: []
        }
    }
}

enum Span: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, year
    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: L.t("Dygn", "Day")
        case .week: L.t("Vecka", "Week")
        case .month: L.t("Månad", "Month")
        case .year: L.t("År", "Year")
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .year: 365 * 86_400
        }
    }

    /// Netatmos skala och vilka typer som hämtas. Max 1024 punkter per anrop.
    func request(for measure: Measure) -> (scale: String, types: String) {
        switch measure {
        case .rain:
            let scale = [Span.day: "1hour", .week: "1day", .month: "1day", .year: "1week"][self]!
            return (scale, "sum_rain")
        case .temperature where self == .month || self == .year:
            return ("1day", "min_temp,max_temp")
        default:
            let scale = [Span.day: "30min", .week: "1hour", .month: "3hours", .year: "1day"][self]!
            let types = switch measure {
            case .wind: "windstrength,guststrength"
            case .co2: "co2"
            default: measure.rawValue
            }
            return (scale, types)
        }
    }
}

struct MeasurePoint: Identifiable, Sendable {
    let date: Date
    let value: Double
    /// Min/max för dygnsvärden, eller byar för vind.
    let low: Double?
    let high: Double?
    var id: Date { date }
}

// MARK: - Nycklar

struct Credentials: Codable, Sendable {
    var clientID: String
    var clientSecret: String
    var refreshToken: String
    var accessToken: String?
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id", clientSecret = "client_secret", refreshToken = "refresh_token"
        case accessToken = "access_token", expiresAt = "expires_at"
    }
}

/// Nycklarna i ~/Library/Application Support/Torpet/netatmo.json, bara läsbar för användaren.
enum CredentialStore {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Torpet/netatmo.json")
    }

    static func load() -> Credentials? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(Credentials.self, from: data)
    }

    static func save(_ c: Credentials) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        try e.encode(c).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - Klient

enum NetatmoError: LocalizedError {
    case notConfigured, tokenRejected, http(Int, String), noStation

    var errorDescription: String? {
        switch self {
        case .notConfigured: L.t("Netatmo-nycklar saknas.", "Netatmo credentials are missing.")
        case .tokenRejected: L.t("Netatmo godtog inte refresh-token. Lägg in en ny under Inställningar.",
                                  "Netatmo rejected the refresh token. Enter a new one in Settings.")
        case .http(let code, let msg): L.t("Netatmo svarade", "Netatmo responded") + " \(code)\(msg.isEmpty ? "" : ": \(msg)")"
        case .noStation: L.t("Ingen väderstation i kontot.", "No weather station in the account.")
        }
    }
}

actor NetatmoClient {
    private var creds: Credentials? = CredentialStore.load()
    /// En förnyelse i taget: två samtidiga skulle använda samma refresh-token och låsa ute appen.
    private var refreshing: Task<String, Error>?
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg)
    }()

    var isConfigured: Bool { creds != nil }
    var current: Credentials? { creds }

    func configure(_ c: Credentials) throws {
        try CredentialStore.save(c)
        creds = c
    }

    func stations() async throws -> [Station] {
        let data = try await authorizedGet("https://api.netatmo.com/api/getstationsdata?get_favorites=false")
        return try Self.parseStations(data)
    }

    func measure(_ measure: Measure, module: Module, span: Span, end: Date = Date()) async throws -> [MeasurePoint] {
        let (scale, types) = span.request(for: measure)
        var c = URLComponents(string: "https://api.netatmo.com/api/getmeasure")!
        c.queryItems = [
            .init(name: "device_id", value: module.deviceID),
            .init(name: "scale", value: scale),
            .init(name: "type", value: types),
            .init(name: "date_begin", value: String(Int(end.timeIntervalSince1970 - span.seconds))),
            .init(name: "date_end", value: String(Int(end.timeIntervalSince1970))),
            .init(name: "optimize", value: "false"),
            .init(name: "real_time", value: "false"),
        ]
        if module.kind != .indoor { c.queryItems!.append(.init(name: "module_id", value: module.id)) }
        let data = try await authorizedGet(c.url!.absoluteString)
        return try Self.parseMeasure(data, measure: measure, types: types)
    }

    // MARK: Anrop

    private func authorizedGet(_ url: String) async throws -> Data {
        var token = try await validToken()
        var (data, code) = try await get(url, token: token)
        if code == 401 || (code == 403 && Self.isTokenError(data)) {
            token = try await refresh()
            (data, code) = try await get(url, token: token)
        }
        guard code == 200 else { throw NetatmoError.http(code, Self.errorMessage(data)) }
        return data
    }

    private func get(_ url: String, token: String) async throws -> (Data, Int) {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("torpet-menubar/1.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func validToken() async throws -> String {
        guard let c = creds else { throw NetatmoError.notConfigured }
        if let t = c.accessToken, !t.isEmpty, let exp = c.expiresAt, exp.timeIntervalSinceNow > 60 { return t }
        return try await refresh()
    }

    private func refresh() async throws -> String {
        if let task = refreshing { return try await task.value }
        let task = Task { try await self.performRefresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        // Läs om från disk: en annan process kan ha förnyat och sparat en ny refresh-token.
        // Har den också fått en ny giltig access token används den direkt.
        if let disk = CredentialStore.load() {
            let mine = creds?.accessToken
            creds = disk
            if let t = disk.accessToken, !t.isEmpty, t != mine,
               let exp = disk.expiresAt, exp.timeIntervalSinceNow > 60 { return t }
        }
        guard var c = creds else { throw NetatmoError.notConfigured }
        var req = URLRequest(url: URL(string: "https://api.netatmo.com/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        req.httpBody = [
            "grant_type=refresh_token",
            "refresh_token=" + enc(c.refreshToken),
            "client_id=" + enc(c.clientID),
            "client_secret=" + enc(c.clientSecret),
        ].joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 || code == 401 || code == 403 { throw NetatmoError.tokenRejected }
        guard code == 200 else { throw NetatmoError.http(code, Self.errorMessage(data)) }

        struct TokenResponse: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Double? }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        c.accessToken = t.access_token
        c.expiresAt = Date().addingTimeInterval(t.expires_in ?? 10_800)
        if let r = t.refresh_token, !r.isEmpty { c.refreshToken = r }
        creds = c
        try CredentialStore.save(c)   // genast: en förlorad ny refresh-token låser ute appen
        return t.access_token
    }

    // MARK: Tolkning

    private static func isTokenError(_ data: Data) -> Bool {
        let code = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error?.code
        return code == 1 || code == 2 || code == 3
    }

    private static func errorMessage(_ data: Data) -> String {
        (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error?.message ?? ""
    }

    static func parseStations(_ data: Data) throws -> [Station] {
        let r = try JSONDecoder().decode(StationsResponse.self, from: data)
        return (r.body.devices ?? []).map { d in
            let base = Module(
                id: d._id, deviceID: d._id, type: d.type ?? "NAMain", name: d.module_name ?? "Inne",
                values: d.dashboard_data ?? [:], dataTypes: d.data_type ?? [], battery: nil, rfStatus: nil,
                wifiStatus: d.wifi_status, reachable: d.reachable ?? true,
                lastSeen: d.last_status_store.map { Date(timeIntervalSince1970: $0) })
            let mods = (d.modules ?? []).map { m in
                Module(
                    id: m._id, deviceID: d._id, type: m.type ?? "", name: m.module_name ?? m.type ?? "Module",
                    values: m.dashboard_data ?? [:], dataTypes: m.data_type ?? [], battery: m.battery_percent,
                    rfStatus: m.rf_status, wifiStatus: nil, reachable: m.reachable ?? true,
                    lastSeen: m.last_seen.map { Date(timeIntervalSince1970: $0) })
            }
            let order: [Module.Kind] = [.indoor, .outdoor, .extraIndoor, .wind, .rain, .unknown]
            let sorted = ([base] + mods).sorted {
                order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)!
            }
            return Station(id: d._id, name: d.station_name ?? d.home_name ?? L.t("Väderstation", "Weather station"),
                           city: d.place?.city, altitude: d.place?.altitude, modules: sorted)
        }
    }

    static func parseMeasure(_ data: Data, measure: Measure, types: String) throws -> [MeasurePoint] {
        struct R: Decodable { let body: [String: [Double?]]? }
        let body = try JSONDecoder().decode(R.self, from: data).body ?? [:]
        let pair = types.contains(",")
        return body.compactMap { key, vals -> MeasurePoint? in
            guard let ts = Double(key), let first = vals.first ?? nil else { return nil }
            let date = Date(timeIntervalSince1970: ts)
            let second = vals.count > 1 ? vals[1] : nil
            switch measure {
            case .wind:
                return MeasurePoint(date: date, value: first / 3.6, low: nil, high: second.map { $0 / 3.6 })
            case .temperature where pair:
                guard let hi = second else { return nil }
                return MeasurePoint(date: date, value: (first + hi) / 2, low: first, high: hi)
            default:
                return MeasurePoint(date: date, value: first, low: nil, high: nil)
            }
        }
        .sorted { $0.date < $1.date }
    }
}
