import SwiftUI

@main
struct MeccaHuntApp: App {
    @State private var appState = AppState(dependencies: .live())

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState.route {
                case .login:
                    LoginView()
                case .map:
                    HuntMapView()
                case .place:
                    PlacementView()
                case .myMeccas:
                    MyMeccasView()
                }
            }
            .environment(appState)
            .environment(appState.dependencies.location)
        }
    }
}
