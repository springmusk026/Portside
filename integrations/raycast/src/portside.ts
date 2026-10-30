import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export type Kind = "dev" | "service" | "container" | "app";

export interface Listener {
  port: number;
  address: string;
}

/** One entry of `portside --json`. Dates arrive as ISO 8601 strings. */
export interface Server {
  id: string;
  kind: Kind;
  title: string;
  detail: string;
  ports: Listener[];
  pid?: number;
  container?: string;
  command: string;
  directory?: string;
  group?: string;
  started?: string;
  memory?: number;
  status?: string;
  source?: string;
}

export const SECTIONS: { kind: Kind; title: string }[] = [
  { kind: "dev", title: "Dev servers" },
  { kind: "service", title: "Services" },
  { kind: "container", title: "Containers" },
  { kind: "app", title: "Apps & system" },
];

const CANDIDATES = [
  "/opt/homebrew/bin/portside",
  "/usr/local/bin/portside",
  "/Applications/Portside.app/Contents/MacOS/Portside",
  join(homedir(), "Applications/Portside.app/Contents/MacOS/Portside"),
];

/** The first Portside binary that exists, preferring an explicit path from preferences. */
export function findBinary(preferred?: string): string | undefined {
  return [preferred, ...CANDIDATES].find((p): p is string => !!p && existsSync(p));
}

export async function listServers(binary: string): Promise<Server[]> {
  // Always ask for everything; the view filters apps out locally so toggling is instant.
  const { stdout } = await execFileAsync(binary, ["--json", "--all"], { timeout: 20_000, maxBuffer: 16 * 1024 * 1024 });
  const parsed: unknown = JSON.parse(stdout);
  return Array.isArray(parsed) ? (parsed as Server[]) : [];
}

/** Runs `portside kill <port>`; resolves with its message, rejects with stderr on exit 1. */
export async function stopPort(binary: string, port: number, force: boolean): Promise<string> {
  const args = ["kill", String(port), ...(force ? ["--force"] : [])];
  try {
    const { stdout } = await execFileAsync(binary, args, { timeout: 30_000 });
    return stdout.trim();
  } catch (error) {
    const e = error as { stderr?: string; stdout?: string; message?: string };
    throw new Error((e.stderr || e.stdout || e.message || "Couldn't stop it").trim());
  }
}

/** Unique port numbers in order (a server often listens on both IPv4 and IPv6). */
export function portNumbers(server: Server): number[] {
  return [...new Set(server.ports.map((p) => p.port))];
}

export function primaryPort(server: Server): number | undefined {
  return server.ports[0]?.port;
}

/** Reachable from other devices on the network, not just this Mac. */
export function isExposed(server: Server): boolean {
  return server.ports.some(
    (p) => !(p.address.startsWith("127.") || p.address === "::1" || p.address === "::ffff:127.0.0.1"),
  );
}

const SCHEMES: [RegExp, string][] = [
  [/postgres/i, "postgres"],
  [/mariadb|mysql/i, "mysql"],
  [/redis|valkey/i, "redis"],
  [/mongo/i, "mongodb"],
];

export function serverURL(server: Server): string | undefined {
  const port = primaryPort(server);
  if (port === undefined) return undefined;
  const text = `${server.detail} ${server.title}`;
  const scheme = SCHEMES.find(([re]) => re.test(text))?.[1] ?? "http";
  return `${scheme}://localhost:${port}`;
}

export function isHTTP(url: string | undefined): url is string {
  return !!url && url.startsWith("http://");
}

export function abbreviate(path: string): string {
  const home = homedir();
  return path === home || path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
}

/** "3h 05m", or Docker's own wording ("Up 3 hours" → "3 hours") for containers. */
export function uptime(server: Server, now = Date.now()): string | undefined {
  if (server.status) return server.status.startsWith("Up ") ? server.status.slice(3) : server.status;
  if (!server.started) return undefined;
  const started = Date.parse(server.started);
  if (Number.isNaN(started)) return undefined;
  const s = Math.max(0, Math.floor((now - started) / 1000));
  const pad = (n: number) => String(n).padStart(2, "0");
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86_400) return `${Math.floor(s / 3600)}h ${pad(Math.floor((s % 3600) / 60))}m`;
  return `${Math.floor(s / 86_400)}d ${pad(Math.floor((s % 86_400) / 3600))}h`;
}

export function formatMemory(bytes: number): string {
  const mb = bytes / 1_048_576;
  return mb >= 1024 ? `${(mb / 1024).toFixed(1)} GB` : `${Math.round(mb)} MB`;
}
