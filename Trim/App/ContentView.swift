import SwiftUI
import Photos
import AppKit

enum AppScreen {
    case setup
    case triage
    case review
    case summary
    case permissionDenied
}

struct ContentView: View {
    @State private var screen: AppScreen = .setup
    @State private var photoService = PhotoLibraryService()
    @State private var settings = AppSettings()
    @State private var session: TriageSession? = nil
    @State private var isLoading: Bool = false
    @State private var deletionResult: DeletionResult? = nil
    @State private var externalDeletionIDs: [String] = []
    @State private var showExternalDeletionPrompt = false
    @State private var libraryExhausted = false

    var body: some View {
        Group {
            switch screen {
            case .setup:
                SessionSetupView(
                    settings: settings,
                    photoService: photoService,
                    hasSavedState: SessionPersistenceService.hasSavedState(),
                    hasPhotos: photoService.hasPhotos(),
                    libraryIsEmpty: !photoService.hasPhotos(),
                    libraryExhausted: libraryExhausted,
                    onStart: { mode in startSession(mode: mode) }
                )
                .overlay {
                    if isLoading {
                        ZStack {
                            Color(nsColor: .windowBackgroundColor).opacity(0.7)
                            ProgressView("Loading photos…")
                        }
                    }
                }

            case .triage:
                if let session = session {
                    TriageView(
                        session: session,
                        settings: settings,
                        onComplete: { screen = .review },
                        onBack: {
                            SessionPersistenceService.save(session: session)
                            screen = .setup
                        },
                        onRequestMore: { requestMorePhotos() }
                    )
                    .onAppear { photoService.startObserving { handleLibraryChange() } }
                    .onDisappear { photoService.stopObserving() }
                }

            case .review:
                if let session = session {
                    ReviewView(
                        session: session,
                        photoService: photoService,
                        onComplete: { result in
                            // Anchor "Continue trimming" at the oldest photo of this completed session
                            let oldestDate = session.items.last?.asset.creationDate
                            settings.setContinueFrom(oldestDate)
                            checkLibraryExhaustion(mode: session.sessionMode, oldestDate: oldestDate)
                            // Apply keep exclusions for all kept items
                            for item in session.itemsToKeep {
                                settings.markKept(identifier: item.id)
                            }
                            SessionPersistenceService.clear()

                            if let result = result, result.filesDeleted > 0 {
                                // Update lifetime stats
                                settings.updateLifetimeStats(
                                    files: result.filesDeleted,
                                    bytes: result.bytesFreed
                                )
                                deletionResult = result
                                self.session = nil
                                screen = .summary
                            } else {
                                self.session = nil
                                screen = .setup
                            }
                        },
                        onCancel: { screen = .triage }
                    )
                }

            case .summary:
                if let result = deletionResult {
                    SessionSummaryView(result: result) {
                        deletionResult = nil
                        screen = .setup
                    }
                }

            case .permissionDenied:
                permissionDeniedView
            }
        }
        .frame(minWidth: 680, idealWidth: 880, minHeight: 720, idealHeight: 960)
        .preferredColorScheme(preferredColorScheme)
        .task { await requestPermissionAndSetup() }
        .confirmationDialog(
            "Photos changed",
            isPresented: $showExternalDeletionPrompt,
            titleVisibility: .visible
        ) {
            Button("Refresh session") { refreshAfterExternalDeletion() }
            Button("Continue", role: .cancel) { dropExternallyDeleted() }
        } message: {
            let n = externalDeletionIDs.count
            Text("\(n) photo\(n == 1 ? "" : "s") in this session \(n == 1 ? "was" : "were") deleted elsewhere.")
        }
    }

    // MARK: - Color scheme

    private var preferredColorScheme: ColorScheme? {
        switch settings.appearanceMode {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    // MARK: - Permission

    private func requestPermissionAndSetup() async {
        let status = await photoService.requestAuthorization()
        switch status {
        case .authorized, .limited:
            break // Good to go
        case .denied, .restricted:
            // Per spec: app closes immediately on permission denied
            NSApplication.shared.terminate(nil)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Session

    private func startSession(mode: SessionMode) {
        libraryExhausted = false
        if mode == .pickUpWhereILeftOff {
            if let restored = SessionPersistenceService.restore(
                using: photoService, settings: settings) {
                session = restored
                screen = .triage
                return
            }
        }

        isLoading = true
        // Capture references on MainActor before going to background thread
        let service = photoService
        let capturedSettings = settings
        let undoSteps = settings.undoSteps
        Task.detached(priority: .userInitiated) {
            let items = service.fetchAssets(for: mode, settings: capturedSettings)
            await MainActor.run {
                let newSession = TriageSession(
                    items: items,
                    mode: mode,
                    maxUndoSteps: undoSteps
                )
                // "I'm feeling lucky" can continue past its cap into the next batch.
                if case .feelingLucky = mode, let cap = capturedSettings.sessionLength.cap {
                    newSession.canRequestMore = items.count == cap
                    newSession.oldestLoadedDate = items.last?.asset.creationDate
                }
                // Consumed the continuation anchor by starting from it.
                if mode == .continueTrimming {
                    settings.setContinueFrom(nil)
                }
                session = newSession
                isLoading = false
                screen = items.isEmpty ? .setup : .triage
            }
        }
    }

    // MARK: - "I'm feeling lucky" continuation

    private func requestMorePhotos() {
        guard let session = session, let date = session.oldestLoadedDate else { return }
        let service = photoService
        let capturedSettings = settings
        let cap = settings.sessionLength.cap ?? 0
        Task.detached(priority: .userInitiated) {
            let newItems = service.fetchAssetsContinuing(
                before: date, cap: cap, settings: capturedSettings)
            await MainActor.run {
                let more = cap > 0 && newItems.count == cap
                session.appendContinuation(
                    newItems,
                    canRequestMore: more,
                    oldestDate: newItems.last?.asset.creationDate ?? date)
            }
        }
    }

    // MARK: - Terminal "End of the road"

    /// After a full-library-tail session (Doom Scroll / Continue trimming), flag the terminal
    /// state when nothing older remains — and clear the now-dead continue anchor.
    private func checkLibraryExhaustion(mode: SessionMode, oldestDate: Date?) {
        guard let oldestDate = oldestDate,
              mode == .doomScroll || mode == .continueTrimming else { return }
        let service = photoService
        let capturedSettings = settings
        Task.detached(priority: .utility) {
            let hasMore = service.hasAssetsOlder(than: oldestDate, settings: capturedSettings)
            await MainActor.run {
                libraryExhausted = !hasMore
                if !hasMore { settings.setContinueFrom(nil) }
            }
        }
    }

    // MARK: - Library change handling

    private func handleLibraryChange() {
        // Permission revoked mid-session → save and close (resumable via Pick up).
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .denied || status == .restricted {
            if let session = session { SessionPersistenceService.save(session: session) }
            NSApplication.shared.terminate(nil)
            return
        }
        // External deletions among the current session's assets.
        guard let session = session else { return }
        let ids = session.items.map(\.id)
        let surviving = Set(photoService.fetchAssets(for: ids).map(\.localIdentifier))
        let missing = ids.filter { !surviving.contains($0) }
        if !missing.isEmpty {
            externalDeletionIDs = missing
            showExternalDeletionPrompt = true
        }
    }

    private func dropExternallyDeleted() {
        rebuildSession(dropping: externalDeletionIDs)
        externalDeletionIDs = []
    }

    private func refreshAfterExternalDeletion() {
        if let session = session { SessionPersistenceService.save(session: session) }
        rebuildSession(dropping: externalDeletionIDs)
        externalDeletionIDs = []
    }

    /// Rebuild the active session without the dropped assets, preserving decisions and
    /// re-locating the current card as closely as possible.
    private func rebuildSession(dropping ids: [String]) {
        guard let old = session else { return }
        let drop = Set(ids)
        let currentID = old.currentItem?.id
        let newItems = old.items.filter { !drop.contains($0.id) }
        guard !newItems.isEmpty else {
            session = nil
            SessionPersistenceService.clear()
            screen = .setup
            return
        }
        let newSession = TriageSession(
            items: newItems, mode: old.sessionMode, maxUndoSteps: old.maxUndoSteps)
        newSession.canRequestMore = old.canRequestMore
        newSession.oldestLoadedDate = old.oldestLoadedDate
        if old.phase == .laterReview {
            let laterIdx = newItems.indices.filter { newItems[$0].decision == .later }
            newSession.laterQueue = Array(laterIdx)
            newSession.laterPosition = 0
            newSession.currentIndex = newItems.count
            newSession.phase = laterIdx.isEmpty ? .complete : .laterReview
        } else if let cid = currentID,
                  let idx = newItems.firstIndex(where: { $0.id == cid }) {
            newSession.currentIndex = idx
        } else {
            newSession.currentIndex = min(old.currentIndex, newItems.count)
        }
        session = newSession
    }

    // MARK: - Permission denied state

    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Photos Access Required")
                .font(.system(size: 20, weight: .semibold))
            Text("Trim needs access to your photo library. Please grant access in System Settings.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button("Open System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos")!)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
