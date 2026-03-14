import Foundation

struct AppLaunchCoordinator {
    func initialDestination() -> AppLaunchDestination {
        // Storage and restoration are not wired yet, so start from the board list.
        .boardList
    }
}
