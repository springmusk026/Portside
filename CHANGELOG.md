# Changelog

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
