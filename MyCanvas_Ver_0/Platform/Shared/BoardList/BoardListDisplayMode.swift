import Foundation

enum BoardListDisplayMode: Int {
    case grid
    case list

    init(segmentIndex: Int) {
        self = BoardListDisplayMode(rawValue: segmentIndex) ?? .grid
    }

    var segmentIndex: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .grid:
            return "Grid"
        case .list:
            return "List"
        }
    }

    static let allCases: [BoardListDisplayMode] = [.grid, .list]
}
