import CopilotCreditsCore
import SwiftUI

@main
struct CopilotCreditsApp: App {
    @StateObject private var store = UsageStore()

#if DEBUG
    init() {
        // scripts/make-tutorial.sh: renders the tutorial frames then quits, without launching the app.
        if let i = CommandLine.arguments.firstIndex(of: "--render-tutorial"), i + 1 < CommandLine.arguments.count {
            Tutorial.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            exit(0)
        }
    }
#endif

    var body: some Scene {
        // .window style: a real SwiftUI panel on click, rather than a classic menu.
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, L10n.locale)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// What shows in the menu bar: icon + percentage.
struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        if let s = store.snapshot, !s.unlimited {
            Image(systemName: s.fractionUsed >= 0.8 ? "exclamationmark.triangle.fill" : "speedometer")
            Text(L10n.percent(s.fractionUsed))
        } else {
            Image(systemName: "speedometer")
        }
    }
}
