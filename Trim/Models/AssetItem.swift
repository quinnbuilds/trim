import Foundation
import Photos

struct AssetItem: Identifiable {
    let id: String           // PHAsset.localIdentifier
    let asset: PHAsset
    var decision: TriageDecision = .undecided
    var fileSize: Int64?
}
