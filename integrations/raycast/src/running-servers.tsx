import {
  Action,
  ActionPanel,
  Alert,
  Color,
  Icon,
  Keyboard,
  List,
  Toast,
  confirmAlert,
  getPreferenceValues,
  open,
  showToast,
} from "@raycast/api";
import { usePromise } from "@raycast/utils";
import { useEffect, useState } from "react";
import {
  Kind,
  SECTIONS,
  Server,
  abbreviate,
  findBinary,
  formatMemory,
  isExposed,
  isHTTP,
  listServers,
  portNumbers,
  primaryPort,
  serverURL,
  stopPort,
  uptime,
} from "./portside";

const REFRESH_MS = 5_000;
const INSTALL_URL = "https://github.com/springmusk026/Portside";

const KIND_ICON: Record<Kind, Icon> = {
  dev: Icon.Code,
  service: Icon.HardDrive,
  container: Icon.Box,
  app: Icon.AppWindow,
};

type Scope = "servers" | "all";

export default function Command() {
  const preferences = getPreferenceValues<Preferences>();
  const binary = findBinary(preferences.portsidePath);

  if (!binary) {
    return (
      <List>
        <List.EmptyView
          icon={Icon.Plug}
          title="Portside isn't installed"
          description="Install Portside from GitHub (or with Homebrew), then run this command again. Raycast looks for it in /opt/homebrew/bin, /usr/local/bin and Applications."
          actions={
            <ActionPanel>
              <Action.OpenInBrowser title="Open Portside on GitHub" url={INSTALL_URL} />
            </ActionPanel>
          }
        />
      </List>
    );
  }

  return <ServerList binary={binary} editor={preferences.editor} />;
}

function ServerList({ binary, editor }: { binary: string; editor?: Preferences["editor"] }) {
  const [scope, setScope] = useState<Scope>("servers");
  const { data, isLoading, error, revalidate } = usePromise(listServers, [binary], {
    failureToastOptions: { title: "Couldn't list ports" },
  });

  useEffect(() => {
    const timer = setInterval(revalidate, REFRESH_MS);
    return () => clearInterval(timer);
  }, [revalidate]);

  const servers = (data ?? []).filter((s) => scope === "all" || s.kind !== "app");
  const toggleApps = () => setScope(scope === "all" ? "servers" : "all");

  return (
    <List
      isLoading={isLoading}
      searchBarPlaceholder="Filter by name, framework, port or folder"
      searchBarAccessory={
        <List.Dropdown tooltip="Show" value={scope} onChange={(v) => setScope(v as Scope)}>
          <List.Dropdown.Item title="Dev Servers, Services & Containers" value="servers" icon={Icon.Code} />
          <List.Dropdown.Item title="Everything, Including Apps" value="all" icon={Icon.AppWindow} />
        </List.Dropdown>
      }
    >
      {error && !data ? (
        <List.EmptyView
          icon={Icon.Warning}
          title="Couldn't run Portside"
          description={error.message}
          actions={
            <ActionPanel>
              <Action title="Refresh" icon={Icon.ArrowClockwise} onAction={revalidate} />
            </ActionPanel>
          }
        />
      ) : (
        <List.EmptyView
          icon={Icon.CheckCircle}
          title={scope === "all" ? "Nothing is listening" : "No dev servers running"}
          description={scope === "all" ? undefined : "Choose “Everything” to include apps and system processes."}
          actions={
            <ActionPanel>
              <Action
                title="Refresh"
                icon={Icon.ArrowClockwise}
                shortcut={Keyboard.Shortcut.Common.Refresh}
                onAction={revalidate}
              />
              <Action
                title={scope === "all" ? "Hide Apps" : "Show Apps"}
                icon={Icon.AppWindow}
                shortcut={{ modifiers: ["cmd", "shift"], key: "a" }}
                onAction={toggleApps}
              />
            </ActionPanel>
          }
        />
      )}
      {SECTIONS.map(({ kind, title }) => {
        const items = servers.filter((s) => s.kind === kind);
        if (items.length === 0) return null;
        return (
          <List.Section key={kind} title={title} subtitle={String(items.length)}>
            {items.map((server) => (
              <ServerItem
                key={server.id}
                server={server}
                binary={binary}
                editor={editor}
                showingApps={scope === "all"}
                onToggleApps={toggleApps}
                onChange={revalidate}
              />
            ))}
          </List.Section>
        );
      })}
    </List>
  );
}

function ServerItem(props: {
  server: Server;
  binary: string;
  editor?: Preferences["editor"];
  showingApps: boolean;
  onToggleApps: () => void;
  onChange: () => void;
}) {
  const { server, binary, editor, onChange } = props;
  const port = primaryPort(server);
  const ports = portNumbers(server);
  const url = serverURL(server);
  const directory = server.directory;
  const where = directory ? abbreviate(directory) : server.container ? `docker: ${server.container}` : server.source;
  const up = uptime(server);

  const accessories: List.Item.Accessory[] = [];
  if (up) accessories.push({ text: up, icon: Icon.Clock, tooltip: `Up ${up}` });
  if (isExposed(server)) {
    accessories.push({
      tag: { value: "LAN", color: Color.Orange },
      tooltip: "Reachable from other devices on the network",
    });
  }
  if (ports.length > 0) {
    accessories.push({
      tag: { value: ports.map((p) => `:${p}`).join(" "), color: Color.Green },
      tooltip:
        [where, server.memory ? formatMemory(server.memory) : undefined].filter(Boolean).join(" · ") || undefined,
    });
  }

  const keywords = [
    ...ports.map(String),
    ...ports.map((p) => `:${p}`),
    server.detail,
    server.container,
    server.source,
    directory,
    directory ? abbreviate(directory) : undefined,
    ...(directory ? directory.split("/").filter(Boolean) : []),
    server.group,
  ].filter((k): k is string => !!k);

  async function stop(force: boolean) {
    if (port === undefined) return;
    if (force) {
      const confirmed = await confirmAlert({
        title: `Force quit ${server.title}?`,
        message: `Sends SIGKILL to whatever holds :${port}. Unsaved work in that process is lost.`,
        primaryAction: { title: "Force Quit", style: Alert.ActionStyle.Destructive },
      });
      if (!confirmed) return;
    }
    const toast = await showToast({ style: Toast.Style.Animated, title: `Stopping ${server.title}…` });
    try {
      const message = await stopPort(binary, port, force);
      toast.style = Toast.Style.Success;
      toast.title = `Stopped ${server.title}`;
      toast.message = message || undefined;
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = `Couldn't stop ${server.title}`;
      toast.message = error instanceof Error ? error.message : String(error);
    }
    onChange();
  }

  return (
    <List.Item
      icon={{ source: KIND_ICON[server.kind], tooltip: server.kind }}
      title={server.title}
      subtitle={server.detail}
      keywords={keywords}
      accessories={accessories}
      actions={
        <ActionPanel>
          <ActionPanel.Section>
            {isHTTP(url) && <Action.OpenInBrowser url={url} />}
            {url && <Action.CopyToClipboard title="Copy URL" content={url} shortcut={Keyboard.Shortcut.Common.Copy} />}
            {directory && <Action.ShowInFinder path={directory} shortcut={{ modifiers: ["cmd", "shift"], key: "f" }} />}
            {directory && (
              <Action
                title={editor ? `Open in ${editor.name}` : "Open in Editor"}
                icon={editor ? { fileIcon: editor.path } : Icon.Code}
                shortcut={Keyboard.Shortcut.Common.Open}
                onAction={() => open(directory, editor)}
              />
            )}
          </ActionPanel.Section>
          <ActionPanel.Section>
            {server.kind !== "app" && port !== undefined && (
              <Action
                title="Stop"
                icon={Icon.Stop}
                style={Action.Style.Destructive}
                shortcut={{ modifiers: ["ctrl"], key: "x" }}
                onAction={() => stop(false)}
              />
            )}
            {port !== undefined && (
              <Action
                title="Force Quit"
                icon={Icon.XMarkCircle}
                style={Action.Style.Destructive}
                shortcut={{ modifiers: ["ctrl", "shift"], key: "x" }}
                onAction={() => stop(true)}
              />
            )}
          </ActionPanel.Section>
          <ActionPanel.Section>
            {server.pid !== undefined && (
              <Action.CopyToClipboard
                title="Copy PID"
                content={String(server.pid)}
                shortcut={{ modifiers: ["cmd", "shift"], key: "p" }}
              />
            )}
            {server.command && (
              <Action.CopyToClipboard
                title="Copy Command"
                content={server.command}
                shortcut={{ modifiers: ["cmd", "shift"], key: "." }}
              />
            )}
            <Action
              title="Refresh"
              icon={Icon.ArrowClockwise}
              shortcut={Keyboard.Shortcut.Common.Refresh}
              onAction={onChange}
            />
            <Action
              title={props.showingApps ? "Hide Apps" : "Show Apps"}
              icon={Icon.AppWindow}
              shortcut={{ modifiers: ["cmd", "shift"], key: "a" }}
              onAction={props.onToggleApps}
            />
          </ActionPanel.Section>
        </ActionPanel>
      }
    />
  );
}
