# LearnHarness for iPhone

An unofficial iOS app for [LearnHarness](https://github.com/amosblomqvist/learnharness): the same
lessons, knowledge graph and settings as the Mac app, on your phone, synced through your own
LearnHarness server.

The app is a native SwiftUI shell around the LearnHarness web UI, the same UI the Mac app wraps
in Electron. That keeps features and looks identical to the desktop app. Native parts:

- Session list, search, filters and session actions (rename, export as Markdown, extract into
  the knowledge graph, delete) in a `NavigationSplitView` with Liquid Glass toolbars
- Sign-in through Safari's sign-in sheet (`ASWebAuthenticationSession`), so password managers
  and passkeys work
- Attachments: files, photos, camera and whole folders, uploaded to the server so the agent can
  read them (the Mac app passes local file paths instead)
- Layout for narrow screens and the foldable iPhone Duo: one column when folded, list and lesson
  side by side when open
- Zoom (⌘+ / ⌘− / ⌘0 with a keyboard), themes follow the server's LearnHarness theme
- English and Dutch

Code comments are in Dutch.

## What you need

- A LearnHarness **server** reachable over HTTPS with `/app-login` and `/app-upload`. The
  desktop app alone is not enough: it only listens on 127.0.0.1. See [`server/`](server/) for a
  complete Docker Compose example (Caddy + Authelia + LearnHarness).
- Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS 27 or later on the device

## Build

```bash
cd ios
cp Local.xcconfig.example Local.xcconfig   # your Team ID, bundle ID prefix, optional server
xcodegen generate
open LearnHarness.xcodeproj
```

Run on your phone from Xcode. With a free Apple account, the app has to be reinstalled every
7 days.

On first launch, enter your server address (for example `learn.example.com`) and sign in.
Tap the address at the bottom of the sign-in screen to change it later.

## Tests

```bash
xcodebuild test -project LearnHarness.xcodeproj -scheme LearnHarness \
  -destination 'platform=iOS Simulator,name=<a simulator>'
node scripts/test-bridge.mjs
```

For a local LearnHarness dev server without a login, start the app in the simulator with the
launch argument `-LHServerURL http://localhost:3917`.

## Versions

The app uses LearnHarness's internal web API, which isn't stable between releases. It was built
against **LearnHarness v0.6.1**; update the server and the app together.

## License

AGPL-3.0, like LearnHarness itself (see [LICENSE](../LICENSE)). Not affiliated with the
LearnHarness authors.
