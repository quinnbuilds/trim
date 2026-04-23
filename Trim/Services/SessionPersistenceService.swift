import Foundation
import Photos

struct PersistedSession: Codable {
    let assetIdentifiers: [String]          // In order
    let decisions: [String: String]         // assetID → decision raw value
    let currentIndex: Int
    let laterQueue: [Int]
    let laterPosition: Int
    let sessionModeRaw: String
    let savedAt: Date
    var continuationStartIdentifier: String?  // For "Continue trimming"
}

class SessionPersistenceService {
    private static let key = "trimSavedSession"
    private static let defaults = UserDefaults.standard

    static func save(session: TriageSession) {
        var decisions: [String: String] = [:]
        for item in session.items where item.decision != .undecided {
            decisions[item.id] = item.decision.rawValue
        }
        let record = PersistedSession(
            assetIdentifiers: session.items.map(\.id),
            decisions: decisions,
            currentIndex: session.currentIndex,
            laterQueue: session.laterQueue,
            laterPosition: session.laterPosition,
            sessionModeRaw: session.sessionMode.serialised,
            savedAt: Date(),
            continuationStartIdentifier: session.items.last?.id
        )
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key)
        }
    }

    static func hasSavedState() -> Bool {
        defaults.data(forKey: key) != nil
    }

    static func load() -> PersistedSession? {
        guard let data = defaults.data(forKey: key),
              let record = try? JSONDecoder().decode(PersistedSession.self, from: data)
        else { return nil }
        return record
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }

    static func clearAllKeeps(settings: AppSettings) {
        settings.clearAllKeeps()
    }

    static func updateLifetimeStats(settings: AppSettings, files: Int, bytes: Int64) {
        settings.updateLifetimeStats(files: files, bytes: bytes)
    }

    // Restore a TriageSession from saved state, re-fetching assets from library
    static func restore(
        using service: PhotoLibraryService,
        settings: AppSettings
    ) -> TriageSession? {
        guard let record = load() else { return nil }

        let assets = service.fetchAssets(for: record.assetIdentifiers)
        guard !assets.isEmpty else { return nil }

        var items = assets.map { AssetItem(id: $0.localIdentifier, asset: $0) }

        // Re-apply decisions
        for i in items.indices {
            if let raw = record.decisions[items[i].id],
               let decision = TriageDecision(rawValue: raw) {
                items[i].decision = decision
            }
        }

        let mode = SessionMode.deserialise(record.sessionModeRaw) ?? .pickUpWhereILeftOff
        let session = TriageSession(
            items: items, mode: .pickUpWhereILeftOff, maxUndoSteps: settings.undoSteps)

        // Restore position (clamped to valid range)
        session.currentIndex = min(record.currentIndex, items.count)
        session.laterQueue = record.laterQueue.filter { $0 < items.count }
        session.laterPosition = min(record.laterPosition, session.laterQueue.count)
        _ = mode // suppress unused warning

        // Re-derive phase
        if session.currentIndex >= items.count {
            if session.laterQueue.isEmpty {
                // Session was complete — shouldn't normally be saved in this state
            } else {
                session.phase = .laterReview
            }
        }

        return session
    }
}
