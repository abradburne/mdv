# Changelog

## 0.5.0 — 2026-06-13

### New

- **Find in document** (⌘F): a search bar above the document with
  find-as-you-type, Find Next (⌘G), Find Previous (⇧⌘G), and a "Not found"
  indicator. Esc or Done closes it.
- **Print and PDF export** (⌘P): prints the rendered document with the active
  style; use the print panel's "Save as PDF" to export.
- **Frontmatter handling**: YAML frontmatter is no longer rendered as a
  literal `---` block. A `title:` in the frontmatter becomes the window
  title. Documents that merely start with a `---` thematic break are left
  untouched, and frontmatter comments no longer show up in the contents
  sidebar.

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
