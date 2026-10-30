# Changelog

## 1.1.0 (2026-10-30)

- **Keyboard control**: ↑↓ pick a row in the panel, ↩ opens it, ⌘C copies its address, ⌘O opens its folder
  in your editor, ⌘⌫ stops it.
- **Global shortcut** to open the panel (Settings, off by default).
- **Group by project**: the servers and Compose containers of one repository in one section, with
  **Stop all** for the project. Also in each row's menu, in either view.
- **Open in your editor**: VS Code, Cursor, Zed, Windsurf, Sublime Text, JetBrains IDEs and more, picked
  in Settings. The row's folder button opens it there. **Open in Terminal** can use iTerm, Ghostty or Warp.
- **Hide and pin**: hide a server you never care about (it moves down with the apps), or pin one to the
  top of its section.
- **Stop forgotten dev servers** after 8 hours, a day or 3 days (Settings, off by default). Pinned
  servers are never stopped.
- Command line: `portside open 3000`, `portside wait 3000` (until something listens; `--free` for the
  opposite), and `portside kill 3000 8000`.
- VoiceOver reads each server and offers Open, Copy and Stop.
- Fix: stopping one server no longer stops another one run by the same runner
  (`concurrently "vite" "uvicorn"`). Stopping both together still stops the runner.
- Fix: stopping a server run by Xcode's Python now stops the runner above it too.
- Fix: the command line could report a stopped server as still running when its parent hadn't
  collected it yet.
- A [Raycast extension](integrations/raycast) and a [Homebrew cask](packaging/homebrew).

## 1.0.2 (2026-10-30)

- Fix: the panel could open too short to show its list, cutting off everything below the search field.

## 1.0.1 (2026-10-30)

- Fix: right after you stopped a server, looking up its port could say "taken by a process Portside can't see".
  Closed connections lingering in TIME_WAIT no longer count as a listener.

## 1.0 (2026-10-30)

First release.

- Menu bar panel listing every dev server, service and container listening on a port, grouped and named by project
- Detects 70+ frameworks and services (Next.js, Vite, Astro, Django, Rails, Postgres, Redis, Ollama…)
- Docker Desktop, OrbStack and Colima: container names instead of the runtime's helper process
- Port lookup: type a port to see who holds it, or that it's free, and free it in one click
- Stop servers, including the `npm`/`pnpm`/`uv` runner above them, with Force Quit when SIGTERM isn't enough
- Warnings for servers reachable from your network, and ones up for over a day
- Copy a network URL to open a dev server on your phone
- Notifications when servers start or stop (optional), launch at login
- `portside` command line: list, look up, kill, `--json`
- Universal app (Apple silicon and Intel) attached to the release
