import Observation

@MainActor
@Observable
final class AppState {
    enum Route: Hashable {
        case home
        case place
        case hunt
    }

    var route: Route = .home
}

