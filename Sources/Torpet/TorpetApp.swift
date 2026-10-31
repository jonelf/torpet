import SwiftUI

struct TorpetApp: App {
    @StateObject private var store = WeatherStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Text(store.menuTitle)
                .monospacedDigit()
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
