# Contributing

Thanks for helping. Portside is small on purpose: one SwiftUI app, no dependencies, no Xcode project.

## Build and run

```sh
./build.sh              # build, install to ~/Applications and launch
./build.sh --no-install # build into build/ only
```

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

Include before/after screenshots for visual changes.

## Scope

Portside reads what's listening and stops it. It doesn't need admin rights, a network connection or a
helper daemon, and features that would require them are out of scope.
