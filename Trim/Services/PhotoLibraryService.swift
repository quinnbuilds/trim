import Foundation
import Photos
import Observation

@Observable
class PhotoLibraryService {
    var authorizationStatus: PHAuthorizationStatus = .notDetermined

    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run { authorizationStatus = status }
        return status
    }

    func hasPhotos() -> Bool {
        let opts = PHFetchOptions()
        opts.fetchLimit = 1
        return PHAsset.fetchAssets(with: opts).count > 0
    }

    // MARK: - Last Night check

    /// Returns true if there are any photos taken from midnight of the previous calendar day
    /// through now that haven't been marked Keep.
    func hasLastNightPhotos(settings: AppSettings) -> Bool {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let startOfYesterday = cal.startOfDay(for: yesterday)

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@", startOfYesterday as NSDate)
        options.fetchLimit = 200

        let result = PHAsset.fetchAssets(with: options)
        var found = false
        result.enumerateObjects { asset, _, stop in
            if !settings.isExcluded(asset.localIdentifier) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: - Asset fetching

    func fetchAssets(for mode: SessionMode, settings: AppSettings) -> [AssetItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false

        let fetchResult: PHFetchResult<PHAsset>

        switch mode {
        case .lastNight:
            // One-week time window (per spec items 10 & 11 — the one-week limit remains
            // as a secondary cap alongside the session length photo count cap).
            let oneWeekAgo = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            options.predicate = NSPredicate(
                format: "creationDate >= %@", oneWeekAgo as NSDate)
            fetchResult = PHAsset.fetchAssets(with: options)

        case .monthYear(let month, let year):
            let start = startOfMonth(month: month, year: year)
            let end = startOfNextMonth(month: month, year: year)
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                start as NSDate, end as NSDate)
            fetchResult = PHAsset.fetchAssets(with: options)

        case .dateRange(let start, let end):
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                start as NSDate, end as NSDate)
            fetchResult = PHAsset.fetchAssets(with: options)

        case .feelingLucky, .pickUpWhereILeftOff, .continueTrimming, .doomScroll:
            fetchResult = PHAsset.fetchAssets(with: options)
        }

        var assets: [PHAsset] = []
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }

        // Apply Keep exclusion
        var filtered = assets.filter { !settings.isExcluded($0.localIdentifier) }

        // Apply mode-specific limits using session length setting
        switch mode {
        case .lastNight:
            if let cap = settings.sessionLength.cap {
                filtered = Array(filtered.prefix(cap))
            }
            // No cap when sessionLength is .doomScroll
        case .feelingLucky:
            if let cap = settings.sessionLength.cap {
                filtered = randomSubset(filtered, count: cap)
            }
            // No cap when sessionLength is .doomScroll
        case .doomScroll:
            // No limit — full library, reverse chronological
            break
        default:
            break
        }

        return filtered.map { AssetItem(id: $0.localIdentifier, asset: $0) }
    }

    // Fetch file sizes for items (called on Review screen for storage estimate)
    func fetchFileSizes(for items: [AssetItem], completion: @escaping ([String: Int64]) -> Void) {
        let assets = items.map(\.asset)
        var sizes: [String: Int64] = [:]
        let group = DispatchGroup()

        for asset in assets {
            group.enter()
            let opts = PHContentEditingInputRequestOptions()
            opts.isNetworkAccessAllowed = false
            asset.requestContentEditingInput(with: opts) { input, _ in
                if let url = input?.fullSizeImageURL {
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                    sizes[asset.localIdentifier] = size
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { completion(sizes) }
    }

    // Restore session from persisted identifiers
    func fetchAssets(for identifiers: [String]) -> [PHAsset] {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { a, _, _ in assets.append(a) }
        // Return in the original order
        let dict = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        return identifiers.compactMap { dict[$0] }
    }

    // MARK: - Helpers

    private func startOfMonth(month: Int, year: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = 1
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func startOfNextMonth(month: Int, year: Int) -> Date {
        let nextMonth = month == 12 ? 1 : month + 1
        let nextYear  = month == 12 ? year + 1 : year
        return startOfMonth(month: nextMonth, year: nextYear)
    }

    private func randomSubset(_ assets: [PHAsset], count: Int) -> [PHAsset] {
        guard assets.count > count else { return assets }
        let start = Int.random(in: 0...(assets.count - count))
        return Array(assets[start..<(start + count)])
    }
}
