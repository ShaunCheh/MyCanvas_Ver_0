import Foundation

struct AppLaunchCoordinator {
    func initialDestination() -> AppLaunchDestination {
        // Storage and restoration are not wired yet, so start in canvas mode.
        .canvas
    }
}
