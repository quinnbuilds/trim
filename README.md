# Trim

A macOS app for rapidly sorting through your photo library. Swipe through cards to Keep, Trim, or defer photos — then delete everything you marked in one shot.

Built to make mass photo cleanup fast and satisfying instead of tedious.

---

## How it works

Trim pulls from your Apple Photos library and presents photos as swipeable cards in reverse chronological order. You make a decision on each one, then confirm deletions at the end.

| Action | Input | Meaning |
|--------|-------|---------|
| Keep | Swipe right / → | Photo survives |
| Trim | Swipe left / ← | Marked for deletion |
| Later | Swipe up / ↑ | Revisit at end of session |
| Undo | Swipe down / ⌘Z | Reverse last decision |
| Full Screen | Space / double-click | View photo — no decision made |

When you finish a session, any **Later** items loop back as a mini-session. Once those are resolved, you see a confirmation grid of everything marked Trim and delete them all at once.

Deleted photos go to Apple's **Recently Deleted** album — nothing is permanent until that clears (30 days).

---

## Session modes

- **Pick up where I left off** — resumes your last unfinished session
- **Feeling lucky** — random sample from your library
- **Last night** — photos from the last 24 hours
- **Month / Year** — photos from a specific month
- **Date range** — custom start and end date
- **Continue trimming** — start a fresh session from where you left off

---

## Requirements

- macOS 14 Sonoma or later
- Photos library access (prompted on first launch)

---

## Build

Open `Trim.xcodeproj` in Xcode and press **Run**.

---

## Distribution

Trim is shared directly as a `.app` — not distributed through the App Store.
