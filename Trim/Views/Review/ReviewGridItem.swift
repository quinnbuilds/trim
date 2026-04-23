import SwiftUI
import Photos

struct ReviewGridItem: View {
    let item: AssetItem
    let onMove: (TriageDecision) -> Void  // .keep or .later

    @State private var thumbnail: NSImage?
    @State private var isHovered: Bool = false
    private let loader = ImageLoader()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Photo
            Group {
                if let img = thumbnail {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Hover overlay with move buttons
            if isHovered {
                HStack(spacing: 6) {
                    moveButton("Keep", color: .green) { onMove(.keep) }
                    moveButton("Later", color: Color(red: 0.75, green: 0.6, blue: 0)) { onMove(.later) }
                }
                .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onHover { isHovered = $0 }
        .onAppear { loadThumbnail() }
        .onDisappear { loader.cancel() }
    }

    private func moveButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.85))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadThumbnail() {
        loader.load(asset: item.asset, targetSize: CGSize(width: 300, height: 300)) { img in
            thumbnail = img
        }
    }
}
