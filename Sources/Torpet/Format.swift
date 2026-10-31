import Foundation

enum Fmt {
    static let sv = Locale(identifier: "sv_SE")

    static func num(_ v: Double, decimals: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(decimals)).locale(sv))
    }

    static func deg(_ v: Double?) -> String { v.map { num($0) + "°" } ?? "–" }

    static func time(_ d: Date) -> String {
        Calendar.current.isDateInToday(d)
            ? d.formatted(.dateTime.hour().minute().locale(sv))
            : d.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(sv))
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return "nyss" }
        if m < 60 { return "\(m) min sedan" }
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
        case "up": "stiger"
        case "down": "sjunker"
        case "stable": "stabil"
        default: s ?? "–"
        }
    }

    static func compass(_ angle: Double) -> String {
        guard angle >= 0 else { return "–" }
        let dirs = ["N", "NNO", "NO", "ONO", "O", "OSO", "SO", "SSO", "S", "SSV", "SV", "VSV", "V", "VNV", "NV", "NNV"]
        return dirs[Int((angle / 22.5).rounded()) % 16] + " (\(Int(angle))°)"
    }

    /// Netatmos rf_status: lägre är bättre (90 svag, 60 stark).
    static func radio(_ v: Int) -> String {
        switch v {
        case ..<70: "stark"
        case ..<80: "medel"
        default: "svag"
        }
    }

    /// wifi_status: 86 svag, 56 stark.
    static func wifi(_ v: Int) -> String {
        switch v {
        case ..<66: "stark"
        case ..<76: "medel"
        default: "svag"
        }
    }

    static func moduleTitle(_ m: Module) -> String {
        switch m.kind {
        case .indoor: "Inne"
        case .outdoor: "Ute"
        case .wind: "Vind"
        case .rain: "Regn"
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
            number(key).map { " kl " + Date(timeIntervalSince1970: $0).formatted(.dateTime.hour().minute().locale(Fmt.sv)) } ?? ""
        }

        add("Temperature", "Temperatur") { Fmt.deg($0) + " " + Fmt.trend(values["temp_trend"]?.string) }
        add("min_temp", "Min i dag") { Fmt.deg($0) + at("date_min_temp") }
        add("max_temp", "Max i dag") { Fmt.deg($0) + at("date_max_temp") }
        if let t = values["temp_trend"]?.string { used.insert("temp_trend"); rows.append(.init(label: "Temperaturtrend", value: Fmt.trendWord(t))) }
        add("Humidity", "Luftfuktighet") { "\(Int($0)) %" }
        add("CO2", "Koldioxid") { "\(Int($0)) ppm" }
        add("Noise", "Ljud") { "\(Int($0)) dB" }
        add("Pressure", "Lufttryck") { Fmt.num($0) + " mbar " + Fmt.trend(values["pressure_trend"]?.string) }
        add("AbsolutePressure", "Absolut tryck") { Fmt.num($0) + " mbar" }
        if let t = values["pressure_trend"]?.string { used.insert("pressure_trend"); rows.append(.init(label: "Trycktrend", value: Fmt.trendWord(t))) }
        add("WindStrength", "Vind") { Fmt.num($0 / 3.6) + " m/s" }
        add("WindAngle", "Vindriktning") { Fmt.compass($0) }
        add("GustStrength", "Byar") { Fmt.num($0 / 3.6) + " m/s" }
        add("GustAngle", "Byarnas riktning") { Fmt.compass($0) }
        add("max_wind_str", "Max vind i dag") { Fmt.num($0 / 3.6) + " m/s" + at("date_max_wind_str") }
        add("max_wind_angle", "Riktning vid max") { Fmt.compass($0) }
        add("Rain", "Regn senaste 5 min") { Fmt.num($0) + " mm" }
        add("sum_rain_1", "Regn senaste timmen") { Fmt.num($0) + " mm" }
        add("sum_rain_24", "Regn i dag") { Fmt.num($0) + " mm" }

        for (k, v) in values.sorted(by: { $0.key < $1.key }) where !used.contains(k) {
            let s: String = switch v {
            case .number(let d): d == d.rounded() ? String(Int(d)) : Fmt.num(d, decimals: 2)
            case .string(let s): s
            case .bool(let b): b ? "ja" : "nej"
            case .other: "–"
            }
            rows.append(ValueRow(label: k, value: s))
        }

        if let b = battery { rows.append(.init(label: "Batteri", value: "\(b) %")) }
        if let r = rfStatus { rows.append(.init(label: "Radiosignal", value: "\(Fmt.radio(r)) (\(r))")) }
        if let w = wifiStatus { rows.append(.init(label: "Wifi", value: "\(Fmt.wifi(w)) (\(w))")) }
        if !reachable { rows.append(.init(label: "Status", value: "Nås inte")) }
        if let m = measuredAt { rows.append(.init(label: "Mätt", value: Fmt.time(m))) }
        return rows
    }
}
