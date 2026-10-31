import SwiftUI

#if DEBUG
// Ritar popovern med exempeldata till en bild, för att se layouten utan Netatmo:
//   swift run Torpet --snapshot ut.png Samples/getstationsdata.json
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > i + 2 {
    MainActor.assumeIsolated {
        Snapshot.render(to: CommandLine.arguments[i + 1], sample: CommandLine.arguments[i + 2])
    }
    exit(0)
}
#endif

TorpetApp.main()
