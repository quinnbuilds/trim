import SwiftUI

/// Color tint overlay that bleeds in as the card is dragged.
/// Action indicator labels (KEEP/TRIM/LATER) are rendered by CardStackView,
/// positioned outside the card in the space below it.
struct SwipeDirectionOverlay: View {
    let offset: CGSize
    let isFullScreen: Bool

    private var decision: TriageDecision? {
        guard !isFullScreen else { return nil }
        let h = offset.width
        let v = offset.height
        let threshold: CGFloat = 30

        if h > threshold { return .keep }
        if h < -threshold { return .trim }
        if v < -threshold { return .later }
        return nil
    }

    private var overlayColor: Color {
        switch decision {
        case .keep:  return .green
        case .trim:  return .red
        case .later: return .yellow
        default:     return .clear
        }
    }

    var overlayOpacity: Double {
        guard let _ = decision else { return 0 }
        let magnitude = max(abs(offset.width), abs(offset.height))
        return min(Double(magnitude - 30) / 140.0, 0.55)
    }

    var body: some View {
        overlayColor
            .opacity(overlayOpacity)
            .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}
