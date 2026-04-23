import SwiftUI

struct SessionSummaryView: View {
    let result: DeletionResult
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Headline
            VStack(spacing: 8) {
                Text(headlineEmoji)
                    .font(.system(size: 64))
                    .padding(.bottom, 4)

                Text(headlineText)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(bytesFreedText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 40)

            // Breakdown
            VStack(spacing: 12) {
                breakdownRow(
                    label: "Trimmed",
                    value: "\(result.filesDeleted)",
                    color: .red,
                    icon: "trash"
                )
                breakdownRow(
                    label: "Kept",
                    value: "\(result.keptCount)",
                    color: .green,
                    icon: "heart"
                )
                if result.laterCount > 0 {
                    breakdownRow(
                        label: "Set to Later",
                        value: "\(result.laterCount)",
                        color: Color(red: 0.75, green: 0.6, blue: 0),
                        icon: "clock"
                    )
                }
            }
            .padding(.horizontal, 60)

            Spacer()

            // Done button
            Button(action: onDone) {
                Text("Done")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Subviews

    private func breakdownRow(label: String, value: String, color: Color, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private var headlineEmoji: String {
        let bytes = result.bytesFreed
        if bytes >= 1_000_000_000 { return "🏆" }
        if bytes >= 500_000_000  { return "🔥" }
        if bytes >= 100_000_000  { return "✂️" }
        return "✨"
    }

    private var headlineText: String {
        let count = result.filesDeleted
        return count == 1 ? "1 photo trimmed" : "\(count) photos trimmed"
    }

    private var bytesFreedText: String {
        guard result.bytesFreed > 0 else { return "Storage freed" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: result.bytesFreed)) freed"
    }
}
