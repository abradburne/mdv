# mdv

Super simple macOS Markdown viewer built with SwiftUI + WebKit. It renders Markdown with markdown-it in a lightweight window, supports live reload, and ships with a few built-in CSS themes.

## Features

- Native macOS app (SwiftUI + AppKit windowing)
- Live reload on file changes
- Built-in styles: Classic, Modern, Minimal
- Opens external links in your browser
- Anchor link support for in-page navigation
- Simple CLI helper (`mdv file.md`) for quick launches

## Requirements

- macOS 12+ (Monterey)
- Swift 6.2 (via Xcode 16 or Swift toolchain that supports 6.2)

## Install & Run

Build and run from the repo:

```sh
swift build
swift run mdv
```

Open a file directly:

```sh
swift run mdv /path/to/file.md
```

## App Usage

- Use **File → Open…** to pick a Markdown file.
- Toggle **Live Reload** to auto-refresh on file changes.
- Switch **Style** from the picker (Classic / Modern / Minimal).
- Use **Reload** to re-render the current file.

## CLI Helper

The app can install a small wrapper script that launches the bundled executable.

1. Open **Settings…** from the app menu.
2. Click **Install CLI Helper**.

Install behavior:

- First tries `/usr/local/bin/mdv`.
- Falls back to `~/bin/mdv` if the first location is not writable.
- If `~/bin` is used, make sure it is on your `PATH`.

After install:

```sh
mdv README.md
```

## Project Layout

- `Sources/mdv/App.swift` — App entry point, windows, views, file watching, CLI helper install.
- `Sources/mdv/MarkdownRenderer.swift` — markdown-it rendering wrapper.
- `Sources/mdv/Resources/*.css` — built-in themes.
- `Sources/mdv/Resources/*.js` — markdown-it + plugins.
- `Tests/MarkdownViewerTests` — renderer tests.

## Tests

```sh
swift test
```

## Notes

- External links open in your default browser.
- In-page anchor links scroll smoothly within the viewer.
