import SwiftUI

@main
struct MeccaHuntApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState.route {
                case .home:
                    HomeView()
                case .place:
                    PlacementView()
                case .hunt:
                    HuntView()
                }
            }
            .environment(appState)
        }
    }
}
