---
name: sticky-note-scrapbook
description: Build and install Sticky Note Scrapbook, a floating to-do note for the Mac desktop styled like a scrapbook page (brass clip, wax seal, or torn paper). Use when the user asks to install, build, update or uninstall Sticky Note Scrapbook from this repository.
---

# Sticky Note Scrapbook

Builds the app from `app/` in this repository and installs it. Building locally means macOS shows no "unidentified developer" warning.

## Install or update

1. Check the Mac: `sw_vers -productVersion` must be 15 or later. If `xcode-select -p` fails, ask the user to run `xcode-select --install`, wait until it finishes, then continue.
2. Build from the repository root: `./app/build.sh`. It prints `built: …/app/build/Sticky Note.app`. If it fails, show the user the first error line.
3. Install: `pkill -x StickyNote; rm -rf "/Applications/Sticky Note.app" && cp -R "app/build/Sticky Note.app" /Applications/`.
4. Open it: `open "/Applications/Sticky Note.app"`. A small brass clip appears near the top-right of the screen, with a Sticky Note icon in the Dock and a paperclip icon in the menu bar.
5. Tell the user, in one short message:
   - Click the clip to open the note; click it again to hide it.
   - The ☰ button in the top-left corner switches between the brass clip, wax seal and torn paper looks.
   - It starts at login; to stop that, use the menu-bar paperclip → Open at Login.

## Uninstall

Quit the app (`pkill -x StickyNote`) and delete `/Applications/Sticky Note.app`. Tasks are stored in `~/Library/Application Support/StickyNote/scrapbook-todos.json`. Only delete that file if the user explicitly asks to remove their tasks too.
