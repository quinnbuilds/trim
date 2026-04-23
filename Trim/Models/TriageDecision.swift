import Foundation

enum TriageDecision: String, Codable, Equatable {
    case keep
    case trim
    case later
    case undecided
}
