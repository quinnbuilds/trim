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
                        }
                    )
                }

            case .review:
                if let session = session {
                    ReviewView(
                        session: session,
                        onComplete: { result in
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
                session = newSession
                isLoading = false
                screen = items.isEmpty ? .setup : .triage
            }
        }
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
