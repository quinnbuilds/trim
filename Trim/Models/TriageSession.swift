import Foundation
import Observation

enum SessionPhase {
    case main
    case laterReview
    case complete
}

@Observable
class TriageSession {
    var items: [AssetItem]
    var currentIndex: Int = 0
    var phase: SessionPhase = .main
    var sessionMode: SessionMode
    var maxUndoSteps: Int

    // Later review: ordered list of indices into `items` that are .later
    var laterQueue: [Int] = []
    var laterPosition: Int = 0

    // Resume support: when a resumed session reviews Later items first, this is the
    // main-queue index to jump back to once the Later pass is exhausted.
    var resumeMainIndexAfterLater: Int? = nil

    // "I'm feeling lucky" continuation: when a capped batch runs out but more of the
    // library remains, pause at the boundary and let the user choose to load more.
    var canRequestMore: Bool = false
    var oldestLoadedDate: Date? = nil
    var pendingContinuation: Bool = false

    // Undo: snapshots full position state before each decision
    private struct UndoEntry {
        let itemIndex: Int
        let previousDecision: TriageDecision
        let phase: SessionPhase
        let mainIndex: Int
        let laterQueue: [Int]
        let laterPosition: Int
        let resumeMainIndexAfterLater: Int?
    }
    private var undoStack: [UndoEntry] = []

    init(items: [AssetItem], mode: SessionMode, maxUndoSteps: Int = 1) {
        self.items = items
        self.sessionMode = mode
        self.maxUndoSteps = maxUndoSteps
    }

    // MARK: - Computed

    var currentItem: AssetItem? {
        switch phase {
        case .main:
            guard currentIndex < items.count else { return nil }
            return items[currentIndex]
        case .laterReview:
            guard laterPosition < laterQueue.count else { return nil }
            return items[laterQueue[laterPosition]]
        case .complete:
            return nil
        }
    }

    var isComplete: Bool { phase == .complete }
    var canUndo: Bool { !undoStack.isEmpty }

    var isLastItem: Bool {
        switch phase {
        case .main:
            guard !items.isEmpty else { return false }
            return currentIndex == items.count - 1
        case .laterReview:
            guard !laterQueue.isEmpty else { return false }
            return laterPosition == laterQueue.count - 1
        case .complete:
            return false
        }
    }

    var totalCount: Int { items.count }

    var progressCount: Int {
        switch phase {
        case .main: return currentIndex
        case .laterReview: return laterPosition
        case .complete: return 0
        }
    }

    var queueCount: Int {
        switch phase {
        case .main: return items.count
        case .laterReview: return laterQueue.count
        case .complete: return 0
        }
    }

    var itemsToTrim: [AssetItem] { items.filter { $0.decision == .trim } }
    var itemsToKeep: [AssetItem] { items.filter { $0.decision == .keep } }
    var estimatedStorageFreed: Int64 { itemsToTrim.compactMap(\.fileSize).reduce(0, +) }

    // MARK: - Actions

    func decide(_ decision: TriageDecision) {
        guard !isComplete else { return }

        let itemIndex: Int
        switch phase {
        case .main:
            guard currentIndex < items.count else { return }
            itemIndex = currentIndex
        case .laterReview:
            guard laterPosition < laterQueue.count else { return }
            itemIndex = laterQueue[laterPosition]
        case .complete:
            return
        }

        let entry = UndoEntry(
            itemIndex: itemIndex,
            previousDecision: items[itemIndex].decision,
            phase: phase,
            mainIndex: currentIndex,
            laterQueue: laterQueue,
            laterPosition: laterPosition,
            resumeMainIndexAfterLater: resumeMainIndexAfterLater
        )
        undoStack.append(entry)
        while undoStack.count > maxUndoSteps { undoStack.removeFirst() }

        items[itemIndex].decision = decision
        advance()
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        items[entry.itemIndex].decision = entry.previousDecision
        phase = entry.phase
        currentIndex = entry.mainIndex
        laterQueue = entry.laterQueue
        laterPosition = entry.laterPosition
        resumeMainIndexAfterLater = entry.resumeMainIndexAfterLater
        pendingContinuation = false
    }

    // MARK: - Private

    private func advance() {
        switch phase {
        case .main:
            currentIndex += 1
            if currentIndex >= items.count {
                if canRequestMore {
                    pendingContinuation = true
                } else {
                    transitionAfterMain()
                }
            }
        case .laterReview:
            laterPosition += 1
            if laterPosition >= laterQueue.count { transitionAfterLater() }
        case .complete:
            break
        }
    }

    private func transitionAfterMain() {
        let laterIndices = items.indices.filter { items[$0].decision == .later }
        if laterIndices.isEmpty {
            phase = .complete
        } else {
            laterQueue = Array(laterIndices)
            laterPosition = 0
            phase = .laterReview
        }
    }

    private func transitionAfterLater() {
        let remainingLater = items.indices.filter { items[$0].decision == .later }
        if remainingLater.isEmpty {
            if let resumeIndex = resumeMainIndexAfterLater, resumeIndex < items.count {
                // Resumed session finished its Later-first pass — drop back into the main queue.
                resumeMainIndexAfterLater = nil
                phase = .main
                currentIndex = resumeIndex
            } else {
                phase = .complete
            }
        } else {
            // Loop again — user marked some Later items as Later again
            laterQueue = Array(remainingLater)
            laterPosition = 0
        }
    }

    // MARK: - Continuation ("I'm feeling lucky")

    /// Append a freshly-fetched batch and resume the main queue at its first item.
    func appendContinuation(_ newItems: [AssetItem], canRequestMore more: Bool, oldestDate: Date?) {
        pendingContinuation = false
        guard !newItems.isEmpty else { finishContinuation(); return }
        let startIndex = items.count
        items.append(contentsOf: newItems)
        canRequestMore = more
        oldestLoadedDate = oldestDate
        phase = .main
        currentIndex = startIndex
    }

    /// Wrap up without loading more — proceed to Later Review / completion as normal.
    func finishContinuation() {
        pendingContinuation = false
        canRequestMore = false
        transitionAfterMain()
    }
}
