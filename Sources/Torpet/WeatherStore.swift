import Foundation
import ServiceManagement

struct SeriesKey: Hashable {
    let moduleID: String
    let measure: Measure
}

@MainActor
final class WeatherStore: ObservableObject {
    @Published var station: Station?
    @Published var fetchedAt: Date?
    @Published var error: String?
    @Published var isLoading = false
    @Published var needsSetup = false
    @Published var showSettings = false

    @Published var series: SeriesKey? { didSet { if series != oldValue { loadHistory() } } }
    @Published var span: Span = .day { didSet { if span != oldValue { loadHistory() } } }
    @Published var history: [MeasurePoint] = []
    @Published var historyError: String?
    @Published var historyLoading = false

    let client = NetatmoClient()
    private var historyCache: [String: (points: [MeasurePoint], at: Date)] = [:]
    private var historyTask: Task<Void, Never>?
    private var started = false
    /// För ögonblicksbilder: aldrig mot nätet.
    var offline = false

    /// Netatmo-stationen skickar data var tionde minut.
    private let interval: TimeInterval = 10 * 60

    func start() {
        guard !started else { return }
        started = true
        Task {
            needsSetup = !(await client.isConfigured)
            showSettings = needsSetup
            while true {
                await refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Hämtar om data är äldre än `ifOlderThan` sekunder.
    func refresh(ifOlderThan age: TimeInterval = 0) async {
        if offline { return }
        if let f = fetchedAt, Date().timeIntervalSince(f) < age { return }
        guard await client.isConfigured, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let stations = try await client.stations()
            guard let s = stations.first else { throw NetatmoError.noStation }
            station = s
            fetchedAt = Date()
            error = nil
            if series == nil, let m = s.outdoor ?? s.indoor { series = SeriesKey(moduleID: m.id, measure: .temperature) }
        } catch NetatmoError.tokenRejected {
            error = NetatmoError.tokenRejected.errorDescription
            needsSetup = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadHistory(force: Bool = false) {
        if offline { return }
        guard let key = series, let module = station?.modules.first(where: { $0.id == key.moduleID }) else { return }
        let cacheKey = "\(key.moduleID)|\(key.measure.rawValue)|\(span.rawValue)"
        // Dygnet hämtas om efter 10 min, längre perioder efter en timme.
        let maxAge: TimeInterval = span == .day ? 600 : 3600
        if !force, let c = historyCache[cacheKey], Date().timeIntervalSince(c.at) < maxAge {
            history = c.points
            historyError = nil
            return
        }
        historyTask?.cancel()
        let span = self.span
        historyLoading = true
        historyTask = Task {
            do {
                let points = try await client.measure(key.measure, module: module, span: span)
                guard !Task.isCancelled else { return }
                historyCache[cacheKey] = (points, Date())
                history = points
                historyError = nil
            } catch {
                guard !Task.isCancelled else { return }
                history = []
                historyError = error.localizedDescription
            }
            historyLoading = false
        }
    }

    func saveCredentials(clientID: String, clientSecret: String, refreshToken: String) async {
        let c = Credentials(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                            refreshToken: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try await client.configure(c)
            needsSetup = false
            showSettings = false
            historyCache = [:]
            await refresh()
            loadHistory(force: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Menyraden

    var menuTitle: String {
        guard let s = station else { return needsSetup ? "Torpet –" : "Torpet …" }
        var parts: [String] = []
        if let t = s.outdoor?.number("Temperature") { parts.append("Ute " + Fmt.deg(t)) }
        if let t = s.indoor?.number("Temperature") { parts.append("Inne " + Fmt.deg(t)) }
        return parts.isEmpty ? "Torpet –" : parts.joined(separator: "  ")
    }

    // MARK: Starta vid inloggning

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                self.error = "Kunde inte ändra start vid inloggning: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
