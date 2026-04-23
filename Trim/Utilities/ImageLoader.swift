import Foundation
import Photos
import AppKit

// Loads a thumbnail for a PHAsset asynchronously.
// Using a class so the request can be cancelled on deinit.
class ImageLoader {
    private var requestID: PHImageRequestID?

    func load(
        asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        completion: @escaping (NSImage?) -> Void
    ) {
        cancel()

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            DispatchQueue.main.async {
                completion(image)
                _ = isDegraded  // accept progressive updates
            }
        }
    }

    func loadFullResolution(
        asset: PHAsset,
        completion: @escaping (NSImage?) -> Void
    ) {
        cancel()

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let targetSize = CGSize(
            width: asset.pixelWidth,
            height: asset.pixelHeight
        )

        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }

    func cancel() {
        guard let id = requestID else { return }
        PHImageManager.default().cancelImageRequest(id)
        requestID = nil
    }

    deinit { cancel() }
}

// Simple prefetch cache wrapper around PHCachingImageManager
class ImagePrefetcher {
    static let shared = ImagePrefetcher()
    private let manager = PHCachingImageManager()

    func startCaching(_ assets: [PHAsset], targetSize: CGSize) {
        manager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func stopCaching(_ assets: [PHAsset], targetSize: CGSize) {
        manager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
}
