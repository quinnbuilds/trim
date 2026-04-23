import SwiftUI
import Photos

/// A single photo card. Loads its thumbnail asynchronously.
struct AssetCardView: View {
    let item: AssetItem
    let size: CGSize

    @State private var thumbnail: NSImage?
    private let loader = ImageLoader()

    var body: some View {
        ZStack {
            // Placeholder while loading
            RoundedRectangle(cornerRadius: 32)
                .fill(Color(nsColor: .windowBackgroundColor))

            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                // Subtle shimmer placeholder
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color.gray.opacity(0.15))
            }

            // Video indicator badge
            if item.asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "video.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                            .padding(16)
                        Spacer()
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
        .onAppear { fetchThumbnail() }
        .onDisappear { loader.cancel() }
        .onChange(of: item.id) { fetchThumbnail() }
    }

    private func fetchThumbnail() {
        thumbnail = nil
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        loader.load(asset: item.asset, targetSize: target) { img in
            thumbnail = img
        }
    }
}
