#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum Snapshot {
    static func render(to path: String, sample: String) {
        let store = WeatherStore()
        store.offline = true
        guard let data = FileManager.default.contents(atPath: sample),
              let station = try? NetatmoClient.parseStations(data).first else {
            print("Kunde inte läsa \(sample)"); return
        }
        store.station = station
        store.fetchedAt = Date().addingTimeInterval(-180)
        store.series = SeriesKey(moduleID: station.outdoor!.id, measure: .temperature)
        let now = Date()
        store.history = (0..<48).map { i in
            let t = Double(i) / 47
            return MeasurePoint(date: now.addingTimeInterval(-86_400 * (1 - t)),
                                value: 4 + 4 * sin(t * .pi * 2 - 1.2) + Double(i % 3) * 0.1, low: nil, high: nil)
        }
        // Ritas i ett riktigt fönster så att knappar och menyer kommer med, till skillnad från ImageRenderer.
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: PopoverView(store: store, scrollable: false)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("Kunde inte rita"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { print("Kunde inte rita"); return }
        try? png.write(to: URL(fileURLWithPath: path))
        print("Sparade \(path) (meny: \(store.menuTitle))")
    }
}
#endif
