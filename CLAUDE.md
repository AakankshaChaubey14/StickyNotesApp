# Sticky Note Scrapbook

A floating to-do list and notepad for the Mac desktop, styled like a scrapbook page. SwiftUI + AppKit, no dependencies, no network. macOS 15 or later, universal (Apple Silicon and Intel). Open source under MIT.

Built by Aakanksha Chaubey (@AakankshaChaubey14, repo owner) and Daria Meshcheriakova (@dmeshcheriakova136), co-developers. Credits live in `README.md` and `AUTHORS`.

## Code map

| File | What's in it |
| --- | --- |
| `app/StickyNote.swift` | `Store` (tasks, notes, undo, saving), the first-run `Intro`, the window/panel, Dock and menu-bar setup, edge snapping, `@main` |
| `app/Note.swift` | The note's views: themes (brass, wax, torn), folded token, sheet, tab bar, task rows, ☰ / ↺ buttons, right-click menus |
| `app/TaskText.swift` | One task line: an `NSTextView` that draws the strike-through and handles keys |
| `app/Notepad.swift` | The Notes page, plus bold / italic shared with task lines (`FormattingTextView`, `FormatController`, `NoteFaces`) |
| `app/Decor.swift` | Drawn decorations: clips, seal, paper edges, stars |
| `app/Snapshot.swift` | Debug-only build (`-D SNAPSHOT`) that renders every state to PNG |
| `app/build.sh`, `app/make-dmg.sh` | Build the app; package it as a `.dmg` |
| `.claude/skills/` | The "Install Sticky Note Scrapbook" skill for end users |
| `.github/` | Issue forms (bug, feature, contact) and README images |
| `handoff/` | The project web page (not hosted yet) |

When adding a Swift file, add it to `SRC=(…)` in `app/build.sh` too.

## Build and run

```sh
./app/build.sh          # -> app/build/Sticky Note.app (universal, ad-hoc signed)
./app/make-dmg.sh       # -> app/build/Sticky.Note.dmg
```

Needs Xcode 16+ or recent Command Line Tools (macOS 15 SDK or newer). Older tools fail on `WindowDragGesture`, `pointerStyle` and `onGeometryChange`.

## Testing without touching real data

**Never test against the user's real tasks and notes.**

- The app reads `~/Library/Application Support/StickyNote/` no matter what `HOME` is set to, so overriding `HOME` does **not** isolate it.
- Point it at a throwaway file instead: `STICKYNOTE_DATA=/tmp/x/todos.json "app/build/Sticky Note.app/Contents/MacOS/StickyNote"`. The notes file then goes next to it.
- Don't run a test copy while the user's own copy is open. Both would write the same files.
- Back up the data folder before installing a new build on someone's Mac.

Snapshot renders, for checking how something looks:

1. Build in a scratch copy:
   ```sh
   swiftc -O -parse-as-library -D SNAPSHOT -target arm64-apple-macosx15.0 -o Snap StickyNote.swift Note.swift TaskText.swift Notepad.swift Decor.swift Snapshot.swift
   ```
2. Put `Snap` in `S.app/Contents/MacOS/`, with the `.ttf` fonts in `S.app/Contents/Resources/`.
3. Run it with `STICKYNOTE_DATA=…` and `SNAPSHOT_DIR=…`.

Things to know:
- It stores its settings under the binary's name (`Snap`). Run `defaults write Snap showInDock -bool false` first, and `defaults delete Snap` after.
- `Snapshot.run` marks two tasks done as part of its checks.

## Data and settings

- Tasks: `scrapbook-todos.json`. `TodoItem.runs` is optional, so older files and versions still read it.
- Notes: `scrapbook-notepad.json`.
- `todos.json` is the old v1 app's file. It's imported once, read-only, and never written.
- First run: if none of those three files exist, `Intro` seeds the teaching tasks and welcome note, and the note opens by itself.
- UserDefaults (bundle `com.aakanksha.stickynote.scrapbook`): `style`, `tab`, `panelX` / `panelY`, `showInDock` (default on), `loginSetupDone`.

## Git and releases

- **`.gitignore` is an allowlist.** Only listed top-level paths are uploaded, so a new top-level file must be added there or it silently never reaches GitHub. Check with `git check-ignore -v <file>`.
- Pushes can fail with HTTP 400 because of the fonts and images. Use `git -c http.postBuffer=524288000 push`.
- Commit under your own name with your GitHub noreply email, so commits link to your profile.
- Ask the person before committing, pushing, releasing or changing repo settings. They like to review first.

To make a release:
1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `app/build.sh`. Update the README if behavior changed. Commit, push.
2. Build from exactly the pushed commit: `git archive <sha> app | tar -x -C <scratch>`, then `./build.sh && ./make-dmg.sh`.
3. Zip with `ditto -c -k --sequesterRsrc --keepParent "Sticky Note.app" Sticky.Note.zip`.
4. `gh release create vX.Y Sticky.Note.dmg Sticky.Note.zip --target <sha> --latest`, with short user-facing notes.
5. Download the assets back and confirm they match what you tested. The README's download button points at `releases/latest/download/Sticky.Note.dmg`, so every release needs a dmg named exactly that.

## Keeping long lists fast

The task list is a `LazyVStack` in a `ScrollView`, and each row is wrapped in `Keyed(key: RowKey…).equatable()` so only rows whose own inputs changed update. Two traps, both measured:
- **Never measure the lazy list's own size** (for example `onGeometryChange` on the `LazyVStack`). That forces every row to lay out and caused multi-second freezes at 300 tasks. The list height is summed from row frames instead (`listHeight`).
- If a row starts depending on new state, add it to `RowKey`, or that row won't update.

The debug snapshot build can time this with a large task file; aim for roughly 15 ms per keystroke at 300 tasks.

## Decisions already made (don't redo these)

- MIT license, copyright both co-developers. Calling it "open source" is accurate.
- macOS 15+ only. Supporting 14 was tried and dropped, since people update often.
- No automatic deletion of ticked tasks. A 6-hour auto-delete was tried and removed.
- The Dock icon is on by default, because a crowded menu bar hides the 📎 icon. Users can turn it off in the 📎 menu.
- Ticked tasks sink below open ones, and new tasks go above ticked ones.
- The tab bar sits at the top of the note and keeps a fixed width, so it never jumps.
- Long task lists scroll inside the note (`Store.maxSheetHeight` caps it to the window and screen).
- The floating panel has **B** and a bullet-list button; the italic button was removed on purpose (⌘I still works). Bullets are plain `• ` text at the start of a line, so they need no data change.
- Bold and italic are stored as flags, not fonts, so they survive switching looks. Torn paper fakes bold with an outline (Courier Prime has no bold). Brass gets a light extra outline, because it already writes in semibold.

## Writing style

Match the surrounding code: short, plain comments that say why, and the existing naming. In user-facing text (README, release notes, UI), keep it short and friendly, and avoid em and en dashes.
