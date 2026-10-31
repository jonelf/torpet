import SwiftUI

struct TorpetApp: App {
    @StateObject private var store = WeatherStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            store.menuLabel
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
