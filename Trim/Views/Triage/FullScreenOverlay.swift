import SwiftUI
import Photos
import AVKit

/// Full-screen photo/video viewer. No swipe decisions allowed while active.
struct FullScreenOverlay: View {
    let asset: PHAsset
    let onDismiss: () -> Void

    @State private var fullResImage: NSImage?
    @State private var avPlayer: AVPlayer?
    @State private var videoLoadFailed: Bool = false
    @FocusState private var isFocused: Bool
    private let loader = ImageLoader()
    @State private var videoRequestID: PHImageRequestID?
    @State private var downloadProgress: Double? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            if asset.mediaType == .video {
                if let player = avPlayer {
                    AVPlayerViewRepresentable(player: player)
                        .padding(40)
                } else if videoLoadFailed {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Unable to load video")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else if let progress = downloadProgress {
                    iCloudDownloadProgress(progress: progress)
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            } else {
                if let img = fullResImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(40)
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.space)  { dismiss(); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onAppear {
            isFocused = true
            if asset.mediaType == .video {
                loadVideo()
            } else {
                loadFullRes()
            }
        }
        .onDisappear {
            loader.cancel()
            if let id = videoRequestID {
                PHImageManager.default().cancelImageRequest(id)
            }
            avPlayer?.pause()
            downloadProgress = nil
        }
        .transition(.opacity)
    }

    private func dismiss() {
        avPlayer?.pause()
        onDismiss()
    }

    private func loadFullRes() {
        loader.loadFullResolution(asset: asset) { img in
            fullResImage = img
        }
    }

    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        options.progressHandler = { (progress: Double, error: Error?, _, _) in
            DispatchQueue.main.async {
                if error != nil {
                    videoLoadFailed = true
                } else {
                    downloadProgress = progress
                }
            }
        }

        let reqID = PHImageManager.default().requestAVAsset(
            forVideo: asset, options: options
        ) { avAsset, _, info in
            DispatchQueue.main.async {
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let fetchError = info?[PHImageErrorKey] as? Error
                if cancelled || fetchError != nil {
                    videoLoadFailed = true
                    return
                }
                guard let avAsset = avAsset else {
                    videoLoadFailed = true
                    return
                }
                let playerItem = AVPlayerItem(asset: avAsset)
                avPlayer = AVPlayer(playerItem: playerItem)
            }
        }
        videoRequestID = reqID
    }

    @ViewBuilder
    private func iCloudDownloadProgress(progress: Double) -> some View {
        VStack(spacing: 16) {
            Text("Downloading… \(Int(progress * 100))%")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 200)
                .tint(.white)
        }
    }
}

private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
