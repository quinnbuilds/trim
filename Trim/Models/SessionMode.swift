import Foundation

enum SessionMode: Equatable {
    case pickUpWhereILeftOff
    case feelingLucky
    case lastNight
    case doomScroll
    case monthYear(month: Int, year: Int)
    case dateRange(start: Date, end: Date)
    case continueTrimming

    var displayName: String {
        switch self {
        case .pickUpWhereILeftOff: return "Pick up where I left off"
        case .feelingLucky: return "I'm feeling lucky"
        case .lastNight: return "Last night wasn't a movie"
        case .doomScroll: return "Doom Scroll"
        case .monthYear(let m, let y):
            let df = DateFormatter()
            df.dateFormat = "MMMM yyyy"
            var comps = DateComponents(); comps.month = m; comps.year = y
            let d = Calendar.current.date(from: comps) ?? Date()
            return df.string(from: d)
        case .dateRange(let s, let e):
            let df = DateFormatter(); df.dateStyle = .short
            return "\(df.string(from: s)) – \(df.string(from: e))"
        case .continueTrimming: return "Continue trimming"
        }
    }

    // Serialisation for persistence
    var serialised: String {
        switch self {
        case .pickUpWhereILeftOff: return "pickUpWhereILeftOff"
        case .feelingLucky: return "feelingLucky"
        case .lastNight: return "lastNight"
        case .doomScroll: return "doomScroll"
        case .continueTrimming: return "continueTrimming"
        case .monthYear(let m, let y): return "monthYear:\(m):\(y)"
        case .dateRange(let s, let e):
            return "dateRange:\(s.timeIntervalSince1970):\(e.timeIntervalSince1970)"
        }
    }

    static func deserialise(_ string: String) -> SessionMode? {
        switch string {
        case "pickUpWhereILeftOff": return .pickUpWhereILeftOff
        case "feelingLucky": return .feelingLucky
        case "lastNight": return .lastNight
        case "doomScroll": return .doomScroll
        case "continueTrimming": return .continueTrimming
        default:
            if string.hasPrefix("monthYear:") {
                let parts = string.split(separator: ":").map(String.init)
                if parts.count == 3, let m = Int(parts[1]), let y = Int(parts[2]) {
                    return .monthYear(month: m, year: y)
                }
            } else if string.hasPrefix("dateRange:") {
                let parts = string.split(separator: ":").map(String.init)
                if parts.count == 3,
                   let s = Double(parts[1]), let e = Double(parts[2]) {
                    return .dateRange(start: Date(timeIntervalSince1970: s),
                                     end: Date(timeIntervalSince1970: e))
                }
            }
            return nil
        }
    }
}
