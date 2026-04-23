import SwiftUI

/// Renders the card stack: top card (interactive) + 2 background cards.
struct CardStackView: View {
    let session: TriageSession
    let isFullScreen: Bool
    @Binding var pendingDecision: TriageDecision?
    let onDecide: (TriageDecision) -> Void
    let onFullScreenRequest: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isAnimatingFlyOff: Bool = false

    var body: some View {
        GeometryReader { geo in
            let cardW = geo.size.width * 0.82
            let cardH = geo.size.height * 0.82
            let cardSize = CGSize(width: cardW, height: cardH)

            ZStack {
                backgroundCard(at: 2, cardSize: cardSize)
                backgroundCard(at: 1, cardSize: cardSize)

                if let item = session.currentItem {
                    AssetCardView(item: item, size: cardSize)
                        .overlay(
                            SwipeDirectionOverlay(
                                offset: isFullScreen ? .zero : dragOffset,
                                isFullScreen: isFullScreen
                            )
                        )
                        .offset(x: dragOffset.width, y: dragOffset.height)
                        .rotationEffect(tiltAngle)
                        .zIndex(10)
                        .gesture(swipeGesture(cardSize: cardSize))
                        .onTapGesture(count: 2) { onFullScreenRequest() }
                }

                // Action indicator labels — positioned below the card and at the card edges
                if !isFullScreen {
                    swipeIndicators(cardW: cardW, cardH: cardH, geoSize: geo.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Keyboard-triggered swipe
        .onChange(of: pendingDecision) { _, newDecision in
            if let decision = newDecision {
                pendingDecision = nil
                triggerFlyOff(decision)
            }
        }
    }

    // MARK: - Swipe indicator labels

    private func swipeIndicators(cardW: CGFloat, cardH: CGFloat, geoSize: CGSize) -> some View {
        let h = dragOffset.width
        let v = dragOffset.height
        let threshold: CGFloat = 30
        let magnitude = max(abs(h), abs(v))
        let labelOpacity = magnitude > threshold
            ? min(Double(magnitude - threshold) / 70.0, 1.0)
            : 0.0

        // Vertical center of the space between card bottom and geo bottom
        let belowCardSpace = (geoSize.height - cardH) / 2
        let labelY = cardH / 2 + belowCardSpace / 2

        let font = Font.system(size: 22, weight: .black, design: .rounded)

        return ZStack {
            if h > threshold {
                Text("KEEP →")
                    .font(font)
                    .foregroundStyle(Color.green)
                    .fixedSize()
                    .offset(x: 0, y: labelY)
            } else if h < -threshold {
                Text("← TRIM")
                    .font(font)
                    .foregroundStyle(Color.red)
                    .fixedSize()
                    .offset(x: 0, y: labelY)
            } else if v < -threshold {
                Text("↑ LATER")
                    .font(font)
                    .foregroundStyle(Color(red: 0.8, green: 0.65, blue: 0))
                    .offset(x: 0, y: labelY)
            }
        }
        .opacity(labelOpacity)
        .allowsHitTesting(false)
    }

    // MARK: - Background cards

    @ViewBuilder
    private func backgroundCard(at depth: Int, cardSize: CGSize) -> some View {
        let idx = backgroundIndex(depth: depth)
        let item: AssetItem? = (idx >= 0 && idx < session.items.count) ? session.items[idx] : nil

        if let item = item {
            AssetCardView(item: item, size: cardSize)
                .scaleEffect(1.0 - Double(depth) * 0.05)
                .offset(y: CGFloat(depth) * 14)
                .zIndex(Double(10 - depth))
                .allowsHitTesting(false)
        }
    }

    private func backgroundIndex(depth: Int) -> Int {
        switch session.phase {
        case .main:
            return session.currentIndex + depth
        case .laterReview:
            let laterIdx = session.laterPosition + depth
            return laterIdx < session.laterQueue.count ? session.laterQueue[laterIdx] : -1
        case .complete:
            return -1
        }
    }

    // MARK: - Gesture & animation

    private var tiltAngle: Angle {
        .degrees(Double(dragOffset.width / 900) * 12)
    }

    private func swipeGesture(cardSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isAnimatingFlyOff, !isFullScreen else { return }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard !isAnimatingFlyOff, !isFullScreen else { return }
                let h = value.translation.width
                let v = value.translation.height
                if      h >  120 { triggerFlyOff(.keep)
                } else if h < -120 { triggerFlyOff(.trim)
                } else if v < -100 { triggerFlyOff(.later)
                } else             { snapBack() }
            }
    }

    func triggerFlyOff(_ decision: TriageDecision) {
        guard !isAnimatingFlyOff else { return }
        isAnimatingFlyOff = true

        withAnimation(.easeIn(duration: 0.26)) {
            dragOffset = flyOffTarget(for: decision)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            onDecide(decision)
            dragOffset = .zero
            isAnimatingFlyOff = false
        }
    }

    private func flyOffTarget(for decision: TriageDecision) -> CGSize {
        switch decision {
        case .keep:  return CGSize(width:  1100, height: dragOffset.height * 0.4)
        case .trim:  return CGSize(width: -1100, height: dragOffset.height * 0.4)
        case .later: return CGSize(width:  dragOffset.width * 0.4, height: -1100)
        default:     return .zero
        }
    }

    private func snapBack() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            dragOffset = .zero
        }
    }
}
