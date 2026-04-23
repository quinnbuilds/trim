# ARCHITECTURE.md — Trim

---

## Overview

Trim is a macOS SwiftUI app. It has three primary screens: Session Setup, Swipe (triage), and Review. State flows in one direction — setup feeds into triage, triage feeds into review, review executes deletion.

---

## Folder structure

```
Trim/
├── Trim.xcodeproj
├── Trim/
│   ├── App/
│   │   ├── TrimApp.swift          # App entry point
│   │   └── ContentView.swift      # Root view, manages screen navigation
│   ├── Models/
│   │   ├── TriageSession.swift    # Session state: current index, decisions, undo stack
│   │   ├── AssetItem.swift        # Wraps PHAsset with classification state
│   │   ├── TriageDecision.swift   # Enum: keep, trim, later
│   │   ├── SessionMode.swift      # Enum: session entry modes
│   │   └── AppSettings.swift      # User-configurable settings
│   ├── Views/
│   │   ├── Setup/
│   │   │   └── SessionSetupView.swift   # Entry screen: session mode selection
│   │   ├── Triage/
│   │   │   ├── TriageView.swift         # Container for swipe session
│   │   │   ├── CardStackView.swift      # Renders stack of cards with depth
│   │   │   ├── AssetCardView.swift      # Individual card: photo + shadow + corners
│   │   │   ├── SwipeDirectionOverlay.swift  # Color tint + label overlay
│   │   │   ├── CardGestureModifier.swift    # Drag, tilt, fly-off animation logic
│   │   │   └── FullScreenOverlay.swift      # Full-screen photo viewing mode
│   │   ├── Review/
│   │   │   ├── ReviewView.swift         # Grid of items marked Trim
│   │   │   └── ReviewGridItem.swift     # Individual item in review grid
│   │   └── Settings/
│   │       ├── SettingsView.swift       # Main settings screen
│   │       └── KeptPhotosView.swift     # Grid of photos previously marked Keep
│   ├── Services/
│   │   ├── PhotoLibraryService.swift    # PHAsset fetching, authorization
│   │   ├── DeletionService.swift        # PHPhotoLibrary.performChanges wrapper
│   │   └── SessionPersistenceService.swift  # Save/restore session state for resume
│   └── Utilities/
│       └── ImageLoader.swift            # Async thumbnail loading, caching
```

---

## Data model

### TriageDecision
```swift
enum TriageDecision {
    case keep
    case trim
    case later
    case undecided
}
```

### AssetItem
Wraps a PHAsset with its current classification state.
```swift
struct AssetItem: Identifiable {
    let id: String           // PHAsset.localIdentifier
    let asset: PHAsset
    var decision: TriageDecision = .undecided
    var fileSize: Int64?     // For storage calculation on Review screen
}
```

### TriageSession
Owns the full array of AssetItems and current index. This is the single source of truth for the swipe session.
```swift
@Observable class TriageSession {
    var items: [AssetItem]
    var currentIndex: Int
    var isComplete: Bool
    var undoStack: [(index: Int, decision: TriageDecision)]  // limited by settings (1–3 steps)
    var sessionMode: SessionMode
    
    func decide(_ decision: TriageDecision)  // advances index, records decision, pushes to undo stack
    func undo()                              // pops undo stack, moves back one card
    var canUndo: Bool                        // computed: undo stack is not empty
    var itemsToTrim: [AssetItem]             // computed: all items where decision == .trim
    var estimatedStorageFreed: Int64         // computed: sum of fileSize for trimmed items
}
```

### SessionMode
```swift
enum SessionMode {
    case pickUpWhereILeftOff
    case feelingLucky
    case lastNight          // "Last night wasn't a movie"
    case monthYear(month: Int, year: Int)
    case dateRange(start: Date, end: Date)
    case continueTrimming
}
```

### AppSettings
```swift
struct AppSettings {
    var undoSteps: Int = 1                    // 1, 2, or 3
    var keepExclusion: KeepExclusion = .oneWeek  // .oneWeek, .oneMonth, .never
    var datePickerFormat: DatePickerFormat = .monthYear  // .monthYear, .dateRange
}
```

---

## Screen flow

```
SessionSetupView (select session mode)
      ↓ (user picks a mode and taps Start)
TriageView (CardStackView) — reverse chronological order
      ↓ (user swipes through all items, or session limit reached)
Later Review (same TriageView, Later items only — Keep / Trim / Later)
      ↓ (all Later items resolved)
ReviewView (confirmation grid of all Trim items)
      ↓ (user confirms)
DeletionService.execute()
      ↓
SessionSetupView (with "Continue trimming" available)
```

If the user **backs out** of a session before completing it, Later items are preserved in the save state and surface first via "Pick up where I left off" on next launch. If the user completes a session with **no Later items**, the flow skips directly from TriageView to ReviewView.

### Session ordering
All sessions proceed **reverse chronologically** — newest photos first, working backward. This applies to every session mode.

### Session persistence
"Pick up where I left off" and "Continue trimming" require persisting session state between app launches. SessionPersistenceService handles saving the current position and any unresolved Later items.

---

## Key technical decisions

**PHPhotoLibrary for all deletion** — Never use direct file system access. All deletion goes through `PHPhotoLibrary.shared().performChanges`. Items land in Apple's "Recently Deleted" — this is intentional.

**Lazy loading** — Never load full-resolution images into the card stack. Use PHImageManager to load thumbnails async. Pre-fetch the next 3–5 cards ahead of the current position.

**Dynamic photo scaling** — All photo display (cards, review grid, Kept photos) sizes dynamically relative to the app window. Never use fixed-size cards or display photos at full resolution in the card view. This ensures the layout works at any window size and supports V2's side-by-side Face-Off mode.

**Full Screen is a viewing mode, not a decision** — Full Screen (Space / double-click) enlarges the current photo to its full resolution or to fill the screen, whichever is smaller. Users must exit Full Screen before making any swipe decision. Exit via Space, Escape, or clicking anywhere.

**Undo via swipe down or ⌘Z** — Undo reverses the last decision and brings back the previous card. The undo stack depth is configurable (1–3 steps) and resets between sessions.

**TriageSession is the single source of truth** — Views never hold decision state themselves. All reads and writes go through TriageSession.

**Reverse chronological ordering** — All sessions proceed from newest to oldest. This is enforced by the session setup logic, not by individual views.

**View files are isolated** — Changes to card appearance and animation never touch model or session code. AssetCardView, SwipeDirectionOverlay, CardGestureModifier, FullScreenOverlay, and CardStackView are purely visual.

**No mid-session confirmation** — TriageView never presents alerts or confirmation dialogs. All confirmation happens on ReviewView only.

---

## Error states and edge cases

These behaviors are defined in PRODUCT.md and must be supported by the relevant services.

**PhotoLibraryService — permission handling:**
- If the user denies Photos permission on first prompt, the app closes immediately.
- If permission is revoked mid-session (via System Settings), the app saves session state via SessionPersistenceService and closes. On relaunch after re-granting, "Pick up where I left off" resumes the session.

**PhotoLibraryService — externally deleted photos:**
- If a photo in the current session stack is detected as deleted outside the app, notify the user, save state, and offer to refresh the session. If the user declines, skip the deleted photo silently.

**DeletionService — failure handling:**
- If `PHPhotoLibrary.performChanges` fails, display "Deletion failed" and open a `.txt` file containing the full error message for debugging via Claude Code.

**SessionPersistenceService — stale state:**
- On session restore, detect whether the underlying photo library has changed since the last save (photos added or deleted externally). If stale, notify the user and rebuild the session automatically, preserving position as closely as possible.

**Edge states:**
- Last photo in a session (not end of library): display "Last photo!" visually before the card is swiped.
- End of library (no Later items, no continuation available): display a terminal message ("End of the road", "All done", "Looking trim").
- Empty photo library: Session Setup shows the same terminal messaging. No session modes available.

---

## Performance requirements

- Must handle libraries of 10,000+ items without freezing UI
- Image loading is always async, never on the main thread
- Card transitions must feel instant — pre-fetch ahead of current position
