import Foundation

enum Fmt {
    static var locale: Locale { Locale(identifier: L.isSwedish ? "sv_SE" : "en_GB") }

    static func num(_ v: Double, decimals: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }

    static func deg(_ v: Double?) -> String { v.map { num($0) + "°" } ?? "–" }

    static func time(_ d: Date) -> String {
        Calendar.current.isDateInToday(d)
            ? d.formatted(.dateTime.hour().minute().locale(locale))
            : d.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return L.t("nyss", "just now") }
        if m < 60 { return L.t("\(m) min sedan", "\(m) min ago") }
        return time(d)
    }

    static func trend(_ s: String?) -> String {
        switch s {
        case "up": "↑"
        case "down": "↓"
        default: ""
        }
    }

    static func trendWord(_ s: String?) -> String {
        switch s {
        case "up": L.t("stiger", "rising")
        case "down": L.t("sjunker", "falling")
        case "stable": L.t("stabil", "stable")
        default: s ?? "–"
        }
    }

    static func compass(_ angle: Double) -> String {
        guard angle >= 0 else { return "–" }
        let dirs = L.isSwedish
            ? ["N", "NNO", "NO", "ONO", "O", "OSO", "SO", "SSO", "S", "SSV", "SV", "VSV", "V", "VNV", "NV", "NNV"]
            : ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return dirs[Int((angle / 22.5).rounded()) % 16] + " (\(Int(angle))°)"
    }

    /// Netatmos rf_status: lägre är bättre (90 svag, 60 stark).
    static func radio(_ v: Int) -> String {
        switch v {
        case ..<70: L.t("stark", "strong")
        case ..<80: L.t("medel", "fair")
        default: L.t("svag", "weak")
        }
    }

    /// wifi_status: 86 svag, 56 stark.
    static func wifi(_ v: Int) -> String {
        switch v {
        case ..<66: L.t("stark", "strong")
        case ..<76: L.t("medel", "fair")
        default: L.t("svag", "weak")
        }
    }

    static func moduleTitle(_ m: Module) -> String {
        switch m.kind {
        case .indoor: L.t("Inne", "Indoor")
        case .outdoor: L.t("Ute", "Outdoor")
        case .wind: L.t("Vind", "Wind")
        case .rain: L.t("Regn", "Rain")
        case .extraIndoor, .unknown: m.name
        }
    }

    static func moduleIcon(_ m: Module) -> String {
        switch m.kind {
        case .indoor: "house"
        case .outdoor: "tree"
        case .wind: "wind"
        case .rain: "cloud.rain"
        case .extraIndoor: "sofa"
        case .unknown: "sensor"
        }
    }
}

struct ValueRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

extension Module {
    /// Alla värden modulen rapporterar, i läsbar ordning. Okända nycklar visas som de är.
    var rows: [ValueRow] {
        var rows: [ValueRow] = []
        var used: Set<String> = ["time_utc", "date_min_temp", "date_max_temp", "date_max_wind_str", "date_max_gust"]
        func add(_ key: String, _ label: String, _ format: (Double) -> String) {
            guard let v = number(key) else { return }
            used.insert(key)
            rows.append(ValueRow(label: label, value: format(v)))
        }
        func at(_ key: String) -> String {
            number(key).map { L.t(" kl ", " at ") + Date(timeIntervalSince1970: $0).formatted(.dateTime.hour().minute().locale(Fmt.locale)) } ?? ""
        }

        add("Temperature", L.t("Temperatur", "Temperature")) { Fmt.deg($0) + " " + Fmt.trend(values["temp_trend"]?.string) }
        add("min_temp", L.t("Min i dag", "Min today")) { Fmt.deg($0) + at("date_min_temp") }
        add("max_temp", L.t("Max i dag", "Max today")) { Fmt.deg($0) + at("date_max_temp") }
        if let t = values["temp_trend"]?.string { used.insert("temp_trend"); rows.append(.init(label: L.t("Temperaturtrend", "Temperature trend"), value: Fmt.trendWord(t))) }
        add("Humidity", L.t("Luftfuktighet", "Humidity")) { "\(Int($0)) %" }
        add("CO2", L.t("Koldioxid", "CO₂")) { "\(Int($0)) ppm" }
        add("Noise", L.t("Ljud", "Noise")) { "\(Int($0)) dB" }
        add("Pressure", L.t("Lufttryck", "Pressure")) { Fmt.num($0) + " mbar " + Fmt.trend(values["pressure_trend"]?.string) }
        add("AbsolutePressure", L.t("Absolut tryck", "Absolute pressure")) { Fmt.num($0) + " mbar" }
        if let t = values["pressure_trend"]?.string { used.insert("pressure_trend"); rows.append(.init(label: L.t("Trycktrend", "Pressure trend"), value: Fmt.trendWord(t))) }
        add("WindStrength", L.t("Vind", "Wind")) { Fmt.num($0 / 3.6) + " m/s" }
        add("WindAngle", L.t("Vindriktning", "Wind direction")) { Fmt.compass($0) }
        add("GustStrength", L.t("Byar", "Gusts")) { Fmt.num($0 / 3.6) + " m/s" }
        add("GustAngle", L.t("Byarnas riktning", "Gust direction")) { Fmt.compass($0) }
        add("max_wind_str", L.t("Max vind i dag", "Max wind today")) { Fmt.num($0 / 3.6) + " m/s" + at("date_max_wind_str") }
        add("max_wind_angle", L.t("Riktning vid max", "Max wind direction")) { Fmt.compass($0) }
        add("Rain", L.t("Regn senaste 5 min", "Rain last 5 min")) { Fmt.num($0) + " mm" }
        add("sum_rain_1", L.t("Regn senaste timmen", "Rain last hour")) { Fmt.num($0) + " mm" }
        add("sum_rain_24", L.t("Regn i dag", "Rain today")) { Fmt.num($0) + " mm" }

        for (k, v) in values.sorted(by: { $0.key < $1.key }) where !used.contains(k) {
            let s: String = switch v {
            case .number(let d): d == d.rounded() ? String(Int(d)) : Fmt.num(d, decimals: 2)
            case .string(let s): s
            case .bool(let b): b ? L.t("ja", "yes") : L.t("nej", "no")
            case .other: "–"
            }
            rows.append(ValueRow(label: k, value: s))
        }

        if let b = battery { rows.append(.init(label: L.t("Batteri", "Battery"), value: "\(b) %")) }
        if let r = rfStatus { rows.append(.init(label: L.t("Radiosignal", "Radio signal"), value: "\(Fmt.radio(r)) (\(r))")) }
        if let w = wifiStatus { rows.append(.init(label: "Wifi", value: "\(Fmt.wifi(w)) (\(w))")) }
        if !reachable { rows.append(.init(label: "Status", value: L.t("Nås inte", "Unreachable"))) }
        if let m = measuredAt { rows.append(.init(label: L.t("Mätt", "Measured"), value: Fmt.time(m))) }
        return rows
    }
}
