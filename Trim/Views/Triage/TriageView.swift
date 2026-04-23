import SwiftUI
import AppKit

/// The main swipe session screen. Hosts the card stack, progress, keyboard handling,
/// and full-screen viewer. Does not touch model code — all state mutations go through session.
struct TriageView: View {
    let session: TriageSession
    let settings: AppSettings
    let onComplete: () -> Void
    let onBack: () -> Void

    @State private var isFullScreen: Bool = false
    @State private var showLastPhoto: Bool = false
    @State private var keyMonitor: Any?
    // Keyboard-triggered swipe: set this to animate the card off programmatically
    @State private var pendingDecision: TriageDecision? = nil

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                CardStackView(
                    session: session,
                    isFullScreen: isFullScreen,
                    pendingDecision: $pendingDecision,
                    onDecide: { decision in handleDecision(decision) },
                    onFullScreenRequest: { withAnimation(.easeInOut(duration: 0.2)) { isFullScreen = true } }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if !isFullScreen {
                    actionHints
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .padding(.top, 8)
                }
            }

            // "Last photo!" banner
            if showLastPhoto && !isFullScreen {
                lastPhotoBanner
            }

            // Full-screen overlay
            if isFullScreen, let item = session.currentItem {
                FullScreenOverlay(asset: item.asset) {
                    withAnimation(.easeOut(duration: 0.2)) { isFullScreen = false }
                }
                .zIndex(100)
            }
        }
        .onAppear {
            setupKeyMonitor()
            showLastPhoto = session.isLastItem
        }
        .onDisappear { teardownKeyMonitor() }
        .onChange(of: session.isComplete) { _, complete in
            if complete { onComplete() }
        }
        .onChange(of: session.isLastItem) { _, isLast in
            withAnimation { showLastPhoto = isLast }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                if session.phase == .laterReview {
                    Text("LATER REVIEW")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                }
                Text("\(session.progressCount + 1) / \(session.queueCount)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(action: handleUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(!session.canUndo)
            .opacity(session.canUndo ? 1 : 0.3)
            .help("Undo (⌘Z)")
        }
    }

    private var actionHints: some View {
        HStack(spacing: 0) {
            actionHint(symbol: "←", label: "TRIM",  color: .red)
            Spacer()
            actionHint(symbol: "↑", label: "LATER", color: Color(red: 0.75, green: 0.6, blue: 0))
            Spacer()
            actionHint(symbol: "→", label: "KEEP",  color: .green)
        }
        .padding(.horizontal, 8)
    }

    private func actionHint(symbol: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.7))
                .tracking(1.5)
        }
    }

    private var lastPhotoBanner: some View {
        VStack {
            HStack {
                Spacer()
                Text("Last photo!")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Capsule())
                    .padding(.top, 60)
                    .padding(.trailing, 20)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func handleDecision(_ decision: TriageDecision) {
        if decision == .keep, let id = session.currentItem?.id {
            settings.markKept(identifier: id)
        }
        session.decide(decision)
    }

    private func handleUndo() {
        guard session.canUndo else { return }
        session.undo()
        withAnimation { showLastPhoto = session.isLastItem }
    }

    // MARK: - Keyboard

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.isFullScreen {
                // Let Space/Escape through to the FullScreenOverlay
                return event
            }
            switch event.keyCode {
            case 124: self.pendingDecision = .keep;  return nil   // →
            case 123: self.pendingDecision = .trim;  return nil   // ←
            case 126: self.pendingDecision = .later; return nil   // ↑
            case 125: self.handleUndo(); return nil               // ↓
            case 6 where event.modifierFlags.contains(.command):  // ⌘Z
                self.handleUndo(); return nil
            case 49: // Space → Full Screen
                withAnimation(.easeInOut(duration: 0.2)) { self.isFullScreen.toggle() }
                return nil
            default: break
            }
            return event
        }
    }

    private func teardownKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }
}
