import Foundation
import Photos
import Observation

@Observable
class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    var authorizationStatus: PHAuthorizationStatus = .notDetermined
    private var changeHandler: (() -> Void)?

    override init() {
        super.init()
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Library change observation

    /// Register a handler invoked (on the main queue) whenever the photo library changes.
    /// Used to detect permission revocation and externally deleted assets during a session.
    func startObserving(_ handler: @escaping () -> Void) {
        changeHandler = handler
        PHPhotoLibrary.shared().register(self)
    }

    func stopObserving() {
        guard changeHandler != nil else { return }
        changeHandler = nil
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in self?.changeHandler?() }
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

        case .continueTrimming:
            // Continue reverse-chronologically past the last completed session.
            if let date = settings.continueFromDate {
                options.predicate = NSPredicate(format: "creationDate < %@", date as NSDate)
            }
            fetchResult = PHAsset.fetchAssets(with: options)

        case .feelingLucky, .pickUpWhereILeftOff, .doomScroll:
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

    /// Next reverse-chronological batch older than `date`, honoring Keep exclusion and an optional cap.
    /// Powers the "I'm feeling lucky" continuation prompt (load the next window).
    func fetchAssetsContinuing(before date: Date, cap: Int, settings: AppSettings) -> [AssetItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false
        options.predicate = NSPredicate(format: "creationDate < %@", date as NSDate)

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { a, _, _ in assets.append(a) }
        var filtered = assets.filter { !settings.isExcluded($0.localIdentifier) }
        if cap > 0 { filtered = Array(filtered.prefix(cap)) }
        return filtered.map { AssetItem(id: $0.localIdentifier, asset: $0) }
    }

    /// Cheap check for whether any non-excluded photo exists older than `date`.
    /// Used to detect a fully-triaged library tail after Doom Scroll / Continue trimming.
    func hasAssetsOlder(than date: Date, settings: AppSettings) -> Bool {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate < %@", date as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
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

    /// Accurate on-disk byte sizes via PHAssetResource — works for photos and videos,
    /// needs no network, and doesn't depend on fullSizeImageURL (which is nil for video).
    func fileSizes(for items: [AssetItem]) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for item in items {
            var total: Int64 = 0
            for resource in PHAssetResource.assetResources(for: item.asset) {
                if let bytes = resource.value(forKey: "fileSize") as? NSNumber {
                    total += bytes.int64Value
                }
            }
            if total > 0 { sizes[item.id] = total }
        }
        return sizes
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

    /// Returns a random contiguous window of `count` assets. Because `assets` is sorted
    /// reverse-chronologically, this lands on a random date and proceeds backward from there
    /// — the "random corner of your library" behavior specified for I'm feeling lucky/frisky.
    private func randomSubset(_ assets: [PHAsset], count: Int) -> [PHAsset] {
        guard assets.count > count else { return assets }
        let start = Int.random(in: 0...(assets.count - count))
        return Array(assets[start..<(start + count)])
    }
}
