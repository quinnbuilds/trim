import Foundation
import Observation

enum KeepExclusion: String, CaseIterable, Codable {
    case oneWeek     = "oneWeek"
    case oneMonth    = "oneMonth"
    case foreverEver = "foreverEver"
    case never       = "never"

    var displayName: String {
        switch self {
        case .oneWeek:     return "One week"
        case .oneMonth:    return "One month"
        case .foreverEver: return "Forever-ever"
        case .never:       return "Never"
        }
    }
}

enum DatePickerFormat: String, CaseIterable, Codable {
    case monthYear  = "monthYear"
    case dateRange  = "dateRange"
}

enum AppearanceMode: String, CaseIterable, Codable {
    case light  = "light"
    case dark   = "dark"
    case system = "system"

    var displayName: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }
}

enum SessionLength: String, CaseIterable, Codable {
    case fifty      = "fifty"
    case oneHundred = "oneHundred"
    case twoHundred = "twoHundred"
    case doomScroll = "doomScroll"

    var displayName: String {
        switch self {
        case .fifty:      return "50"
        case .oneHundred: return "100"
        case .twoHundred: return "200"
        case .doomScroll: return "Doom Scroll"
        }
    }

    /// nil means no cap (Doom Scroll)
    var cap: Int? {
        switch self {
        case .fifty:      return 50
        case .oneHundred: return 100
        case .twoHundred: return 200
        case .doomScroll: return nil
        }
    }
}

@Observable
class AppSettings {
    var undoSteps: Int = 1
    var keepExclusion: KeepExclusion = .oneWeek
    var datePickerFormat: DatePickerFormat = .monthYear
    var appearanceMode: AppearanceMode = .dark
    var sessionLength: SessionLength = .oneHundred
    // assetID -> date marked Keep
    var keptAssetIdentifiers: [String: Date] = [:]
    // Lifetime stats
    var totalFilesDeleted: Int = 0
    var totalBytesFreed: Int64 = 0

    private let defaults = UserDefaults.standard

    init() { load() }

    func load() {
        let raw = defaults.integer(forKey: "undoSteps")
        undoSteps = raw < 1 ? 1 : min(raw, 3)

        if let s = defaults.string(forKey: "keepExclusion") {
            // Migration: old raw value "never" meant "Never show again" (= foreverEver).
            // Check migration flag so we only do this once.
            if s == "never" && !defaults.bool(forKey: "keepExclusionMigrated") {
                keepExclusion = .foreverEver
                defaults.set(KeepExclusion.foreverEver.rawValue, forKey: "keepExclusion")
                defaults.set(true, forKey: "keepExclusionMigrated")
            } else if let v = KeepExclusion(rawValue: s) {
                keepExclusion = v
            }
        }

        if let s = defaults.string(forKey: "datePickerFormat"),
           let v = DatePickerFormat(rawValue: s) { datePickerFormat = v }
        if let s = defaults.string(forKey: "appearanceMode"),
           let v = AppearanceMode(rawValue: s) { appearanceMode = v }
        if let s = defaults.string(forKey: "sessionLength"),
           let v = SessionLength(rawValue: s) { sessionLength = v }
        if let data = defaults.data(forKey: "keptAssets"),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            keptAssetIdentifiers = decoded
        }
        totalFilesDeleted = defaults.integer(forKey: "totalFilesDeleted")
        totalBytesFreed = Int64(defaults.double(forKey: "totalBytesFreed"))
    }

    func save() {
        defaults.set(undoSteps, forKey: "undoSteps")
        defaults.set(keepExclusion.rawValue, forKey: "keepExclusion")
        defaults.set(datePickerFormat.rawValue, forKey: "datePickerFormat")
        defaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
        defaults.set(sessionLength.rawValue, forKey: "sessionLength")
        if let data = try? JSONEncoder().encode(keptAssetIdentifiers) {
            defaults.set(data, forKey: "keptAssets")
        }
        defaults.set(totalFilesDeleted, forKey: "totalFilesDeleted")
        defaults.set(Double(totalBytesFreed), forKey: "totalBytesFreed")
    }

    func markKept(identifier: String) {
        keptAssetIdentifiers[identifier] = Date()
        save()
    }

    func unmarkKept(identifier: String) {
        keptAssetIdentifiers.removeValue(forKey: identifier)
        save()
    }

    func clearAllKeeps() {
        keptAssetIdentifiers.removeAll()
        save()
    }

    func updateLifetimeStats(files: Int, bytes: Int64) {
        totalFilesDeleted += files
        totalBytesFreed += bytes
        save()
    }

    func isExcluded(_ identifier: String) -> Bool {
        guard let date = keptAssetIdentifiers[identifier] else { return false }
        switch keepExclusion {
        case .never:
            // Never exclude — Kept photos always re-appear in sessions
            return false
        case .foreverEver:
            return true
        case .oneWeek:
            guard let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) else { return false }
            return date >= cutoff
        case .oneMonth:
            guard let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return false }
            return date >= cutoff
        }
    }
}
