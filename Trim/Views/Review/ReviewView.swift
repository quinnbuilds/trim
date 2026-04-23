import SwiftUI
import Photos
import AppKit

struct ReviewView: View {
    let session: TriageSession
    let onComplete: (DeletionResult?) -> Void
    let onCancel: () -> Void

    @State private var isDeletionInProgress: Bool = false
    @State private var deletionError: String? = nil

    private var trimItems: [AssetItem] { session.itemsToTrim }
    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onCancel) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Review")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()

                // Placeholder to balance the back button
                Image(systemName: "chevron.left")
                    .opacity(0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if trimItems.isEmpty {
                emptyState
            } else {
                // Stats bar
                statsBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)

                Divider()

                // Photo grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(trimItems) { item in
                            ReviewGridItem(item: item) { newDecision in
                                session.items[itemIndex(item)].decision = newDecision
                            }
                        }
                    }
                    .padding(16)
                }

                Divider()

                // Delete button
                deleteButton
                    .padding(20)
            }
        }
        .alert("Deletion Failed", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK") { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
    }

    // MARK: - Subviews

    private var statsBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trimItems.count) photo\(trimItems.count == 1 ? "" : "s") to delete")
                    .font(.system(size: 15, weight: .semibold))
                if session.estimatedStorageFreed > 0 {
                    Text("~\(formattedBytes(session.estimatedStorageFreed)) freed")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("Tap a photo to move it back to Keep or Later")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Nothing to delete")
                .font(.system(size: 20, weight: .semibold))
            Text("All photos were marked Keep or Later.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Button("Done") { onComplete(nil) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var deleteButton: some View {
        Button(action: performDeletion) {
            Group {
                if isDeletionInProgress {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 200)
                } else {
                    Text("Delete \(trimItems.count) Photo\(trimItems.count == 1 ? "" : "s")")
                        .frame(minWidth: 200)
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.large)
        .disabled(isDeletionInProgress || trimItems.isEmpty)
    }

    // MARK: - Actions

    private func itemIndex(_ item: AssetItem) -> Int {
        session.items.firstIndex(where: { $0.id == item.id }) ?? 0
    }

    private func performDeletion() {
        isDeletionInProgress = true
        let assets = trimItems.map(\.asset)
        // Capture result metadata before deletion
        let result = DeletionResult(
            filesDeleted: trimItems.count,
            bytesFreed: session.estimatedStorageFreed,
            keptCount: session.itemsToKeep.count,
            laterCount: session.items.filter { $0.decision == .later }.count
        )

        Task {
            do {
                try await DeletionService.delete(assets: assets)
                await MainActor.run { onComplete(result) }
            } catch {
                let logURL = DeletionService.writeErrorLog(error, assets: assets)
                await MainActor.run {
                    isDeletionInProgress = false
                    deletionError = error.localizedDescription
                    if let url = logURL {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
