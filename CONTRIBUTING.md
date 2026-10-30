# Contributing

Thanks for helping. Portside is small on purpose: one SwiftUI app, no dependencies, no Xcode project.

## Build and run

```sh
./build.sh              # build, install to ~/Applications and launch
./build.sh --no-install # build into build/ only
./test.sh               # run the tests (Tests/Tests.swift)
```

The tests need no Xcode project or XCTest: they compile with the app's sources and use a small `expect`.
Add a case when you teach Portside a new framework, and run them before a PR (CI does too).

You need the Xcode command line tools (Swift 6) and macOS 14 or later.

## Teaching Portside a new framework or service

Most contributions will be this, and it's a one-line change in `Sources/Model.swift`:

- **A dev framework** (found from the command line): add a `(word, "Name")` pair to `Catalog.frameworks`.
  The word is the executable or package name as it appears in the process's arguments, such as `vite` or `@sveltejs/kit`.
  Order matters: put specific tools before generic runners.
- **A service with its own binary** (a database, a tunnel): add `"binary": "Name"` to `Catalog.services`.
- **A service on the JVM or Erlang**: add to `Catalog.argServices`.
- **A connection string** (`postgres://`): add to `Catalog.schemes`.

Check it with `build/Portside.app/Contents/MacOS/Portside --json` while the server runs.

## Design changes

The panel is built from the tokens in `Sources/Design.swift` (spacing, type, semantic colors). Render every
state in light and dark with demo data and look at them before opening a PR:

```sh
build/Portside.app/Contents/MacOS/Portside --snapshot /tmp/portside-shots
```

Include before/after screenshots for visual changes. The README animation is rendered the same way:

```sh
build/Portside.app/Contents/MacOS/Portside --demo-gif docs/demo.gif
```

## Releasing

```sh
./build.sh --release   # universal build/Portside.zip, and its SHA-256 for the Homebrew cask
```

With a Developer ID certificate, `SIGN_IDENTITY="Developer ID Application: …"` and
`NOTARY_PROFILE=<profile>` (from `xcrun notarytool store-credentials`) also notarize and staple it.
Then update the cask as described in [packaging/homebrew](packaging/homebrew/README.md).

## Scope

Portside reads what's listening and stops it. It doesn't need admin rights, a network connection or a
helper daemon, and features that would require them are out of scope.
