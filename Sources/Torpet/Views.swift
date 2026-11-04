import Charts
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: WeatherStore
    /// Av för ögonblicksbilder: ImageRenderer ritar inte innehållet i en ScrollView.
    var scrollable = true
    @State private var contentHeight: CGFloat = 0
    /// Så högt som skärmen tillåter, med plats för rubrik och sidfot.
    private var maxHeight: CGFloat { max((NSScreen.main?.visibleFrame.height ?? 800) - 140, 300) }

    var body: some View {
        VStack(spacing: 0) {
            Header(store: store)
            Divider()
            if scrollable {
                // En ScrollView i menyradsfönstret saknar egen höjd och krymper till noll, så höjden mäts.
                ScrollView {
                    content.padding(14)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: HeightKey.self, value: g.size.height)
                        })
                }
                .frame(height: min(max(contentHeight, 60), maxHeight))
                .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
            } else {
                content.padding(14)
            }
            Divider()
            Footer(store: store)
        }
        .frame(width: 440)
        .id(store.language)   // ritar om allt när språket byts
        .task { await store.refresh(ifOlderThan: 120) }
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let e = store.error {
                Label(e, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.showSettings || store.needsSetup {
                SettingsView(store: store)
            } else if let s = store.station {
                Overview(station: s)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)],
                          alignment: .leading, spacing: 10) {
                    ForEach(s.modules.filter { $0.kind == .outdoor } + s.modules.filter { $0.kind != .outdoor }) { ModuleCard(module: $0) }   // utomhus till vänster, som i översikten
                }
                HistoryView(store: store, station: s)
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(30)
            }
        }
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct Header: View {
    @ObservedObject var store: WeatherStore

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.station?.name ?? "Torpet").font(.headline)
                if let s = store.station {
                    let place = [s.city, s.altitude.map { "\(Int($0)) " + L.t("m ö.h.", "m a.s.l.") }].compactMap { $0 }.joined(separator: " · ")
                    let measured = (s.outdoor ?? s.indoor)?.measuredAt.map { L.t("Mätt ", "Measured ") + Fmt.time($0) } ?? ""
                    Text([place, measured].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { Task { await store.refresh(); store.loadHistory(force: true) } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless).help(L.t("Hämta nu", "Refresh now"))
            Button { store.showSettings.toggle() } label: {
                Image(systemName: store.showSettings ? "xmark.circle" : "gearshape")
            }
            .buttonStyle(.borderless).help(L.t("Inställningar", "Settings"))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct Footer: View {
    @ObservedObject var store: WeatherStore

    var body: some View {
        HStack {
            if let f = store.fetchedAt {
                Text(L.t("Hämtad ", "Fetched ") + Fmt.ago(f)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L.t("Avsluta", "Quit")) { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

private struct Overview: View {
    let station: Station

    var body: some View {
        HStack(spacing: 0) {
            big(L.t("Ute", "Outdoor"), station.outdoor, icon: "tree")
            Divider().frame(height: 54)
            big(L.t("Inne", "Indoor"), station.indoor, icon: "house")
        }
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func big(_ title: String, _ m: Module?, icon: String) -> some View {
        VStack(spacing: 2) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.deg(m?.number("Temperature")))
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                Text(Fmt.trend(m?.values["temp_trend"]?.string)).font(.title3).foregroundStyle(.secondary)
            }
            if let m, let lo = m.number("min_temp"), let hi = m.number("max_temp") {
                Text("\(Fmt.deg(lo)) – \(Fmt.deg(hi))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ModuleCard: View {
    let module: Module

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(Fmt.moduleTitle(module), systemImage: Fmt.moduleIcon(module)).font(.subheadline.weight(.semibold))
                Spacer()
                if !module.reachable { Image(systemName: "wifi.slash").foregroundStyle(.orange) }
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                ForEach(module.rows) { r in
                    GridRow {
                        Text(r.label).foregroundStyle(.secondary)
                        Text(r.value).monospacedDigit().gridColumnAlignment(.trailing)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Historik

private struct HistoryView: View {
    @ObservedObject var store: WeatherStore
    let station: Station

    private var options: [(SeriesKey, String)] {
        station.modules.flatMap { m in
            Measure.available(for: m).map { (SeriesKey(moduleID: m.id, measure: $0), "\(Fmt.moduleTitle(m)) · \($0.label)") }
        }
    }

    private var measure: Measure { store.series?.measure ?? .temperature }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.t("Historik", "History")).font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $store.series) {
                    ForEach(options, id: \.0) { Text($0.1).tag(Optional($0.0)) }
                }
                .labelsHidden().fixedSize()
            }
            Picker("", selection: $store.span) {
                ForEach(Span.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            ZStack {
                chart.frame(height: 170)
                if store.historyLoading && store.history.isEmpty { ProgressView() }
                if let e = store.historyError { Text(e).font(.caption).foregroundStyle(.orange) }
                else if !store.historyLoading && store.history.isEmpty { Text(L.t("Ingen data", "No data")).font(.caption).foregroundStyle(.secondary) }
            }
            summary
        }
        .onAppear { if store.history.isEmpty { store.loadHistory() } }
    }

    private var unit: String { measure.unit }
    private var avgName: String { L.t("Medel", "Average") }
    private var gustName: String { L.t("Byar", "Gusts") }

    @ViewBuilder private var chart: some View {
        let pts = store.history
        let ranged = pts.contains { $0.low != nil }
        Chart {
            ForEach(pts) { p in
                switch measure {
                case .rain:
                    BarMark(x: .value("Tid", p.date), y: .value("mm", p.value))
                        .foregroundStyle(.blue)
                case .wind:
                    LineMark(x: .value("Tid", p.date), y: .value("m/s", p.value), series: .value("Serie", avgName))
                        .foregroundStyle(by: .value("Serie", avgName))
                    if let g = p.high {
                        LineMark(x: .value("Tid", p.date), y: .value("m/s", g), series: .value("Serie", gustName))
                            .foregroundStyle(by: .value("Serie", gustName))
                    }
                default:
                    if ranged, let lo = p.low, let hi = p.high {
                        AreaMark(x: .value("Tid", p.date), yStart: .value("Min", lo), yEnd: .value("Max", hi))
                            .foregroundStyle(.red.opacity(0.18))
                    }
                    LineMark(x: .value("Tid", p.date), y: .value(measure.label, p.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartForegroundStyleScale([avgName: Color.teal, gustName: Color.orange])
        .chartLegend(measure == .wind ? .visible : .hidden)
        .chartYScale(domain: yDomain(pts))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisGridLine()
                AxisValueLabel(collisionResolution: .greedy) {
                    if let d = v.as(Date.self) { Text(axisLabel(d)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.num(d, decimals: 0) + (unit == "°" ? "°" : "")) } }
            }
        }
    }

    /// Spannet tas från datan, med min/max och byar, så hela kurvan och ytan alltid syns.
    private func yDomain(_ pts: [MeasurePoint]) -> ClosedRange<Double> {
        guard !pts.isEmpty else { return 0...1 }
        var lo = pts.map { min($0.low ?? $0.value, $0.value) }.min()!
        var hi = pts.map { max($0.high ?? $0.value, $0.value) }.max()!
        if measure == .rain || measure == .wind { lo = min(lo, 0) }
        let pad = max((hi - lo) * 0.08, 0.5)
        if measure != .rain && measure != .wind { lo -= pad }
        hi += pad
        return lo...hi
    }

    private var color: Color {
        switch measure {
        case .temperature: .red
        case .humidity: .cyan
        case .co2: .green
        case .pressure: .purple
        case .noise: .gray
        case .rain: .blue
        case .wind: .teal
        }
    }

    private func axisLabel(_ d: Date) -> String {
        switch store.span {
        case .day: d.formatted(.dateTime.hour().minute().locale(Fmt.locale))
        case .week: d.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.locale))
        case .month: d.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.locale))
        case .year: d.formatted(.dateTime.month(.abbreviated).locale(Fmt.locale))
        }
    }

    @ViewBuilder private var summary: some View {
        let pts = store.history
        if !pts.isEmpty {
            let decimals = (measure == .co2 || measure == .noise || measure == .humidity) ? 0 : 1
            let f = { (v: Double) in Fmt.num(v, decimals: decimals) + (unit == "°" ? "°" : " " + unit) }
            let lo = pts.map { $0.low ?? $0.value }.min()!
            let hi = pts.map { $0.high ?? $0.value }.max()!
            let avg = pts.map(\.value).reduce(0, +) / Double(pts.count)
            Group {
                if measure == .rain {
                    Text(L.t("Totalt", "Total") + " \(f(pts.map(\.value).reduce(0, +)))  ·  " + L.t("Mest", "Most") + " \(f(hi))")
                } else if measure == .wind {
                    Text(L.t("Medel", "Average") + " \(f(avg))  ·  " + L.t("Starkaste by", "Strongest gust") + " \(f(hi))")
                } else {
                    Text("Min \(f(lo))  ·  Max \(f(hi))  ·  " + L.t("Medel", "Average") + " \(f(avg))")
                }
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

// MARK: - Inställningar

struct SettingsView: View {
    @ObservedObject var store: WeatherStore
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var refreshToken = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Netatmo").font(.subheadline.weight(.semibold))
            Text(L.t("Skapa en app på dev.netatmo.com (My apps). Kopiera client ID och client secret, och ta fram en refresh-token med Token generator, scope read_station. Använd en egen token här: Netatmo byter token vid varje förnyelse, så två ställen med samma token låser ute det ena.",
                     "Create an app at dev.netatmo.com (My apps). Copy the client ID and client secret, and generate a refresh token with the Token generator, scope read_station. Use a token of its own here: Netatmo replaces the token on every renewal, so two clients sharing one lock each other out."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Client ID", text: $clientID)
            SecureField("Client secret", text: $clientSecret)
            SecureField("Refresh token", text: $refreshToken)
            HStack {
                Link(L.t("Öppna dev.netatmo.com", "Open dev.netatmo.com"), destination: URL(string: "https://dev.netatmo.com/apps/")!).font(.caption)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button(L.t("Spara", "Save")) {
                    saving = true
                    Task {
                        await store.saveCredentials(clientID: clientID, clientSecret: clientSecret, refreshToken: refreshToken)
                        refreshToken = ""
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(clientID.isEmpty || clientSecret.isEmpty || refreshToken.isEmpty || saving)
            }
            Divider()
            Picker(L.t("Språk", "Language"), selection: $store.language) {
                ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle(L.t("Starta vid inloggning", "Launch at login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
            Text(L.t("Nycklarna sparas i ", "Credentials are stored in ") + CredentialStore.url.path(percentEncoded: false) + ".")
                .font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
        }
        .textFieldStyle(.roundedBorder)
        .task {
            if let c = await store.client.current {
                clientID = c.clientID
                clientSecret = c.clientSecret
            }
        }
    }
}
