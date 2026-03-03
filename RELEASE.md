# Release (CLI)

This produces a signed, notarized DMG containing `mdv.app`.

Prereqs
- Developer ID Application cert installed.
- App-specific password for `alan@xenocode.co.jp`.

One-time: store notarization credentials
```sh
xcrun notarytool store-credentials "mdv-notary" \
  --apple-id "alan@xenocode.co.jp" \
  --team-id "HVUXZ635F3" \
  --password "app-specific-password"
```

Build + sign + notarize
```sh
sh scripts/release.sh
```

Output
- `mdv.dmg`

Notes
- Bundle ID: `jp.co.xenocode.mdv`
- Version: `0.3.0`
