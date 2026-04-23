import Foundation
import Photos
import AppKit

struct DeletionResult {
    let filesDeleted: Int
    let bytesFreed: Int64
    let keptCount: Int
    let laterCount: Int
}

enum DeletionError: LocalizedError {
    case unknown
    case partial(message: String)

    var errorDescription: String? {
        switch self {
        case .unknown: return "An unknown error occurred during deletion."
        case .partial(let msg): return msg
        }
    }
}

class DeletionService {
    static func delete(assets: [PHAsset]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? DeletionError.unknown)
                }
            }
        }
    }

    @discardableResult
    static func writeErrorLog(_ error: Error, assets: [PHAsset]) -> URL? {
        let content = """
        Trim Deletion Error Log
        =======================
        Date: \(Date())

        Error: \(error.localizedDescription)

        Full error:
        \(error)

        Assets attempted (\(assets.count)):
        \(assets.map { "  - \($0.localIdentifier)" }.joined(separator: "\n"))
        """

        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(
            "trim_deletion_error_\(Int(Date().timeIntervalSince1970)).txt")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
