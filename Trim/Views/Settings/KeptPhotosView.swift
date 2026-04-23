import SwiftUI
import Photos

struct KeptPhotosView: View {
    @Bindable var settings: AppSettings
    let photoService: PhotoLibraryService

    @State private var keptItems: [AssetItem] = []
    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 8)]

    var body: some View {
        Group {
            if keptItems.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "heart.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No kept photos")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Photos you mark Keep will appear here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(keptItems) { item in
                            KeptGridItem(item: item, onUnKeep: {
                                settings.unmarkKept(identifier: item.id)
                                keptItems.removeAll { $0.id == item.id }
                            })
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear { loadKeptItems() }
        .navigationTitle("My Keeps")
    }

    private func loadKeptItems() {
        let identifiers = Array(settings.keptAssetIdentifiers.keys)
        let assets = photoService.fetchAssets(for: identifiers)
        keptItems = assets.map { AssetItem(id: $0.localIdentifier, asset: $0) }
    }
}

private struct KeptGridItem: View {
    let item: AssetItem
    let onUnKeep: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered: Bool = false
    private let loader = ImageLoader()

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if isHovered {
                Button("Un-Keep", action: onUnKeep)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(8)
                    .buttonStyle(.plain)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onHover { isHovered = $0 }
        .onAppear {
            loader.load(asset: item.asset, targetSize: CGSize(width: 200, height: 200)) { img in
                thumbnail = img
            }
        }
        .onDisappear { loader.cancel() }
    }
}
