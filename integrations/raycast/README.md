# Portside for Raycast

See what's listening on your ports, from Raycast. Dev servers, databases and containers, with the
project they belong to, and a way to stop them.

This extension is a front end for [Portside](https://github.com/springmusk026/Portside), a macOS menu bar app.
It reads the list from Portside's command line (`portside --json --all`) and stops servers with
`portside kill <port>`. Nothing leaves your Mac.

## Requirements

Portside must be installed. The extension looks for it, in order, at:

- `/opt/homebrew/bin/portside`
- `/usr/local/bin/portside`
- `/Applications/Portside.app/Contents/MacOS/Portside`
- `~/Applications/Portside.app/Contents/MacOS/Portside`

If it lives somewhere else, set **Portside Binary** in the extension preferences.

## Running Servers

Lists everything listening, in sections: Dev servers, Services, Containers. Apps and system processes
are hidden; choose **Everything, Including Apps** in the dropdown (or ⌘⇧A) to show them.

Each row shows the port, a **LAN** tag when the server is reachable from other devices, and how long
it has been up. Hover the port for the project folder. Search matches the name, framework, port
(`3000` or `:3000`) and folder.

| Action                                           | Shortcut |
| ------------------------------------------------ | -------- |
| Open in Browser (HTTP servers)                   | ↵        |
| Copy URL (`http://`, `postgres://`, `redis://`…) | ⌘⇧C      |
| Show in Finder                                   | ⌘⇧F      |
| Open in Editor                                   | ⌘O       |
| Stop                                             | ⌃X       |
| Force Quit (asks first)                          | ⌃⇧X      |
| Copy PID                                         | ⌘⇧P      |
| Copy Command                                     | ⌘⇧.      |
| Refresh                                          | ⌘R       |
| Show / Hide Apps                                 | ⌘⇧A      |

The list also refreshes every 5 seconds while open.

## Preferences

- **Editor**: the app Open in Editor uses. Empty means the default app for folders.
- **Portside Binary**: a path to `portside`, if it isn't in one of the standard places.

## Development

```sh
npm install
npm run dev     # ray develop
npm run build   # ray build
npm run lint    # ray lint
```

## License

MIT
