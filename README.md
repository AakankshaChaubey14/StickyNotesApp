# Sticky Note Scrapbook

A to-do note that hangs on your Mac desktop like a page from a scrapbook. It folds down to a single brass clip, wax seal or torn-paper scrap, shows your next two tasks when opened, and the whole list when you ask for it. When a list isn't enough, flip it over to a notes page.

<p align="center">
  <img src=".github/images/sticky-note.webp" alt="Sticky Note Scrapbook in the brass clip look: a torn-edged paper note with To-do and Notes tabs, bold and italic buttons, and two tasks" width="440">
</p>

**Requires** macOS 15 or later. Universal build (Apple Silicon and Intel).

## Get it

**Download:** grab `Sticky.Note.zip` from [Releases](../../releases/latest), unzip it, drag **Sticky Note** into Applications and open it. If macOS says it can't check the app: System Settings → Privacy & Security → Open Anyway.

**With Claude Code:** clone this repo, run `claude` inside it, and say *Install Sticky Note Scrapbook*. Claude builds it on your Mac with the skill in `.claude/skills/`, so there's no security prompt.

**Build it yourself:** with Xcode 16 or later, or recent Command Line Tools (macOS 15 SDK or newer), run `./app/build.sh`, then copy `app/build/Sticky Note.app` to Applications.

## Using it

The first time you open it, the note shows you around with a few tips you can tick off.

- Click the clip, seal or scrap to open the note; click it again to fold it away. Folding tucks it against the nearest screen edge.
- Tick a task and it moves below the open ones. Hover a task and click **×** to delete it.
- **To-do | Notes** at the top switches between your list and a notes page for everything else.
- Select words and press **B** or *I* (or ⌘B, ⌘I) to make them bold or italic, in notes and tasks alike.
- **5 more** shows every task; **Show less** goes back to two.
- ☰ (top left) switches the look. ↺ (top right) clears the page you're on, tasks or notes, with a 5-second Undo.
- ⌘C ⌘X ⌘V ⌘A ⌘Z work. Pasting a list adds one task per line.
- Near a screen edge, the note glides itself into view when it opens.
- It sits in the Dock: click the icon to open the note, right-click it to quit. Right-clicking the note or the folded clip has Quit too. Prefer it off the Dock? Untick **Show in Dock** in the 📎 menu-bar menu.

Tasks and notes stay on your Mac in `~/Library/Application Support/StickyNote/` (`scrapbook-todos.json` and `scrapbook-notepad.json`). No accounts, no network.

## Project

| Path | What |
| --- | --- |
| `app/` | SwiftUI + AppKit source, `build.sh`, bundled fonts and icon |
| `app/Notepad.swift` | The Notes page and the bold / italic formatting shared with tasks |
| `app/Snapshot.swift` | Debug-only build (`-D SNAPSHOT`): renders every state to PNG and runs the paste and fit-on-screen checks |
| `handoff/` | The project's web page |
| `.claude/skills/` | The Claude Code install skill |
| `.github/` | Feedback forms and the README picture |

## Feedback

We'd love to hear how you use it and what you'd change.

- 💡 Ideas, questions or general feedback: [Discussions](../../discussions)
- 🐞 Something not working? [Report a bug](../../issues/new?template=bug_report.yml)
- ✨ Want something new? [Request a feature](../../issues/new?template=feature_request.yml)
- 💼 Business use, collaboration or anything else: [Get in touch](../../issues/new?template=contact.yml)

## Credits

Dreamed up and built by **Aakanksha Chaubey** ([@AakankshaChaubey14](https://github.com/AakankshaChaubey14))  
Designed and dressed by **Daria Meshcheriakova** ([@dmeshcheriakova136](https://github.com/dmeshcheriakova136))

*Co-developed with care, one sticky note at a time.*

Fonts: Cormorant Garamond, EB Garamond and Courier Prime, all under the SIL Open Font License (`app/Resources/OFL.txt`).
