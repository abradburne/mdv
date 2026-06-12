# Changelog

## 0.4.0 — 2026-06-12

### New

- **Redesigned Settings window** in the macOS System Settings style: sections
  in a left sidebar (Appearance, Command Line) with grouped preference panes.
- **Appearance preferences**: choose the default style (Classic, Modern,
  Minimal) and adjust the font size (12–24 px). Changes apply to all open
  windows immediately.
- **DMG installer layout**: the disk image now opens with large icons and a
  drag-to-Applications arrangement.

### Fixed

- **⌘H now hides the app** — Hide, Hide Others, and Show All were missing from
  the app menu.
- **Installing the CLI helper no longer crashes** (a main-actor isolation trap
  in the background installer).
- **The `mdv` command now works reliably**: it resolves the installed app
  bundle correctly, brings the window to the front, and reports errors in the
  terminal instead of failing silently.
- Reopening the Settings window after closing it no longer risks a crash.

## 0.3.1 and earlier

See the [GitHub releases](https://github.com/abradburne/mdv/releases).
