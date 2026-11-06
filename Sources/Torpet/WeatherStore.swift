import SwiftUI
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
    @Published var language: AppLanguage = L.lang {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: L.key) }
    }

    @Published var series: SeriesKey? { didSet { if series != oldValue { loadHistory() } } }
    @Published var span: Span = .day { didSet { if span != oldValue { loadHistory() } } }
    @Published var history: [MeasurePoint] = []
    @Published var historyError: String?
    @Published var historyLoading = false
    /// Vilken temperatur menyraden visar just nu; räknas upp var sjunde minut.
    @Published private var menuIndex = 0

    let client = NetatmoClient()
    private var historyCache: [String: (points: [MeasurePoint], at: Date)] = [:]
    private var historyTask: Task<Void, Never>?
    private var started = false
    /// För ögonblicksbilder: aldrig mot nätet.
    var offline = false

    /// Netatmo-stationen skickar data var tionde minut.
    private let interval: TimeInterval = 10 * 60
    /// Menyraden växlar mellan ute och inne så här ofta.
    private let menuCycle: TimeInterval = 7 * 60

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
        Task {
            while true {
                try? await Task.sleep(for: .seconds(menuCycle))
                menuIndex += 1
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

    /// Temperatur för menyraden: (SF Symbol, värde). Växlar mellan ute och inne, ute först.
    private var menuParts: [(icon: String, value: String)] {
        guard let s = station else { return [] }
        var parts: [(icon: String, value: String)] = []
        if let t = s.outdoor?.number("Temperature") { parts.append(("tree", Fmt.deg(t))) }
        if let t = s.indoor?.number("Temperature") { parts.append(("house", Fmt.deg(t))) }
        guard !parts.isEmpty else { return [] }
        return [parts[menuIndex % parts.count]]
    }

    private var menuFallback: String {
        station == nil ? (needsSetup ? "Torpet –" : "Torpet …") : "Torpet –"
    }

    /// Menyraden visar inte symboler inuti Text, så etiketten ritas som en mallbild
    /// (template) som systemet färgar för ljust/mörkt läge.
    var menuLabel: some View {
        let parts = menuParts
        return Group {
            if parts.isEmpty {
                Text(menuFallback)
            } else if let img = Self.menuImage(parts) {
                Image(nsImage: img)
            } else {
                Text(menuTitle)
            }
        }
    }

    private static func menuImage(_ parts: [(icon: String, value: String)]) -> NSImage? {
        let view = HStack(spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                HStack(spacing: 3) {
                    Image(systemName: p.icon)
                    Text(p.value).monospacedDigit().lineLimit(1).fixedSize()
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.black)
        .padding(.vertical, 1)
        .fixedSize()
        let r = ImageRenderer(content: view)
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let img = r.nsImage else { return nil }
        img.isTemplate = true
        return img
    }

    var menuTitle: String {
        let parts = menuParts
        return parts.isEmpty ? menuFallback : parts.map { "[\($0.icon)] \($0.value)" }.joined(separator: "  ")
    }

    // MARK: Starta vid inloggning

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                self.error = L.t("Kunde inte ändra start vid inloggning: ", "Couldn't change launch at login: ") + error.localizedDescription
            }
            objectWillChange.send()
        }
    }
}
