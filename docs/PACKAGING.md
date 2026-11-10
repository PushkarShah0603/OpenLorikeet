# Build and distribution

Run `./scripts/package.sh` on a Mac with Swift 6 and macOS 15 or newer. The script builds the app for the current architecture, creates the icon representations from `docs/assets/lorikeet.png`, checks the bundle signature, and validates the ZIP. The selected artwork is the second supplied lorikeet variant. The animated companion is drawn with native AppKit shapes.

The default package is ad-hoc signed for local development. LibreOffice, Pandoc, and Tectonic are optional user-installed engines. The package includes the Swift app and icon, with no copies of those executables.

For distribution with a Developer ID identity, set `LORIKEET_SIGN_IDENTITY` when running the packaging script. This enables hardened runtime and timestamped signing. Submit the resulting ZIP using an existing notarytool Keychain profile. After Apple accepts the submission, staple and validate the app, then recreate the ZIP with the stapled bundle.

```sh
LORIKEET_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package.sh
xcrun notarytool submit dist/OpenLorikeet-macOS-arm64.zip --keychain-profile OpenLorikeet --wait
xcrun stapler staple dist/OpenLorikeet.app
xcrun stapler validate dist/OpenLorikeet.app
ditto -c -k --sequesterRsrc --keepParent dist/OpenLorikeet.app dist/OpenLorikeet-notarized.zip
```

Substitute the ZIP for the target architecture if needed. The local package has passed extraction and signature checks. Developer ID signing, notarization, and graphical testing on a separate Mac are pending.

Launch at login uses Service Management and may require approval in macOS Login Items. [Apple Service Management documentation](https://developer.apple.com/documentation/servicemanagement/smappservice)
