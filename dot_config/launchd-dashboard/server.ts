// launchd dashboard: read-only view of the per-user LaunchAgents in ~/Library/LaunchAgents.
// Served at https://launchd.localhost by the local.launchd-dashboard LaunchAgent (Caddy proxies 127.0.0.1:8479).
// launchd keeps no run history, so the server samples `launchctl print` and appends run/exit transitions to a JSONL file.

import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";

const HOME = homedir();
const PORT = Number(process.env.LAUNCHD_DASHBOARD_PORT ?? 8479);
const AGENTS_DIR = join(HOME, "Library/LaunchAgents");
const CHEZMOI_AGENTS_DIR = join(HOME, ".local/share/chezmoi/Library/LaunchAgents");
const STATE_HOME = process.env.XDG_STATE_HOME ?? join(HOME, ".local/state");
const STATE_DIR = join(STATE_HOME, "launchd-dashboard");
const HISTORY_FILE = join(STATE_DIR, "history.jsonl");
const SAMPLE_MS = 15_000;
const HISTORY_LIMIT = 2000;
const LOG_TAIL_BYTES = 64 * 1024;
const LOG_TAIL_LINES = 200;
const ALLOWED_HOSTS = new Set(["launchd.localhost", "launchd.localhost:443", `127.0.0.1:${PORT}`, `localhost:${PORT}`]);
const ERROR_PATTERN = /\b(error|err|fatal|panic|fail(ed|ure)?|exception|traceback)\b/i;

type Plist = Record<string, unknown>;
type CalendarEntry = Partial<Record<"Month" | "Day" | "Weekday" | "Hour" | "Minute", number>>;

export type Schedule = {
  keepAlive: boolean;
  runAtLoad: boolean;
  interval?: number;
  calendar: CalendarEntry[];
  watchPaths: string[];
  summary: string;
};

export type LiveState = {
  loaded: boolean;
  state?: string;
  pid?: number;
  runs?: number;
  lastExit?: string;
};

export type HistoryEvent = { ts: string; label: string; kind: "start" | "exit"; pid?: number; exit?: string };

// ---------------------------------------------------------------------------- #
//                                    CATALOG                                   #
// ---------------------------------------------------------------------------- #

// The dashboard's own agent is hidden: it is always running whenever the page loads.
const SELF_LABEL = "local.launchd-dashboard";

// Groups render in this order; `icon` names an SVG defined in index.html.
export const GROUPS = ["Finance", "AI agents", "Local web", "Shell & SSH", "Mac health", "App updaters", "Other"];

export type Profile = { name: string; icon: string; group: string; description: string; url?: string };

const CATALOG: Record<string, Profile> = {
  "local.prb-pulse": {
    name: "Pulse",
    icon: "activity",
    group: "Finance",
    description: "Personal finance dashboard",
    url: "https://pulse.localhost",
  },
  "local.our-house-budget": {
    name: "Household budget",
    icon: "wallet",
    group: "Finance",
    description: "Our House budget app",
    url: "https://budget.localhost",
  },
  "com.prb.claude.gaszip-refund-check": {
    name: "Gas.zip refund check",
    icon: "receipt",
    group: "Finance",
    description: "One-shot Claude task checking a bridge refund",
  },
  "local.ai-coord-api": {
    name: "Coordination API",
    icon: "server",
    group: "AI agents",
    description: "ai-coord server for agent scopes and findings",
  },
  "local.ai-coord-dashboard": {
    name: "Coordination board",
    icon: "dashboard",
    group: "AI agents",
    description: "Live view of agent sessions and claims",
    url: "https://coord.localhost",
  },
  "local.ai-handoffs": {
    name: "Handoffs",
    icon: "handoff",
    group: "AI agents",
    description: "Task handoff inbox",
    url: "https://handoffs.localhost",
  },
  "local.caddy": {
    name: "HTTPS proxy",
    icon: "lock",
    group: "Local web",
    description: "Caddy serving the *.localhost domains",
  },
  "local.caddy-tls-watchdog": {
    name: "HTTPS watchdog",
    icon: "shield",
    group: "Local web",
    description: "Checks TLS hourly and restarts Caddy on failure",
  },
  "local.atuin-daemon": {
    name: "Shell history",
    icon: "history",
    group: "Shell & SSH",
    description: "Atuin daemon recording shell history",
  },
  "local.ssh-load-keychain": {
    name: "SSH key loader",
    icon: "key",
    group: "Shell & SSH",
    description: "Adds the GitHub key to ssh-agent at login",
  },
  "local.ssd-write-monitor": {
    name: "SSD write monitor",
    icon: "drive",
    group: "Mac health",
    description: "Daily check of disk write volume",
  },
  "homebrew.mxcl.sleepwatcher": {
    name: "Sleep & wake hooks",
    icon: "moon",
    group: "Mac health",
    description: "Runs ~/.sleep and ~/.wakeup",
  },
  "com.google.GoogleUpdater.wake": {
    name: "Google updater",
    icon: "download",
    group: "App updaters",
    description: "Wakes Google Updater for Chrome updates",
  },
  "com.google.keystone.agent": {
    name: "Google Keystone",
    icon: "download",
    group: "App updaters",
    description: "Legacy Google software updater",
  },
  "com.google.keystone.xpcservice": {
    name: "Google Keystone service",
    icon: "download",
    group: "App updaters",
    description: "Helper service for Keystone",
  },
  "com.macpaw.CleanMyMac5.Updater": {
    name: "CleanMyMac updater",
    icon: "download",
    group: "App updaters",
    description: "Checks for CleanMyMac 5 updates",
  },
};

// Unknown labels: "com.example.sync-worker" -> "Sync worker".
export function humanize(label: string): string {
  const words = (label.split(".").at(-1) ?? label)
    .replace(/[-_]+/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function describeAgent(label: string): Profile {
  const known = CATALOG[label];
  if (known) return known;
  if (/updater|keystone/i.test(label)) {
    const vendor = label.split(".")[1] ?? label;
    return { name: `${humanize(vendor)} updater`, icon: "download", group: "App updaters", description: label };
  }
  return { name: humanize(label), icon: "box", group: "Other", description: label };
}

// ---------------------------------------------------------------------------- #
//                                    PARSING                                   #
// ---------------------------------------------------------------------------- #

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function describeCalendar(entry: CalendarEntry): string {
  const time = `${entry.Hour === undefined ? "every hour" : pad(entry.Hour)}:${pad(entry.Minute ?? 0)}`;
  const parts = [entry.Hour === undefined ? `hourly at :${pad(entry.Minute ?? 0)}` : `at ${time}`];
  if (entry.Weekday !== undefined) parts.push(`on ${WEEKDAYS[entry.Weekday]}`);
  if (entry.Day !== undefined) parts.push(`on day ${entry.Day}`);
  if (entry.Month !== undefined) parts.push(`of month ${entry.Month}`);
  if (entry.Weekday === undefined && entry.Day === undefined && entry.Hour !== undefined) parts.unshift("daily");
  return parts.join(" ");
}

export function describeInterval(seconds: number): string {
  if (seconds % 86_400 === 0) return `every ${seconds / 86_400}d`;
  if (seconds % 3600 === 0) return `every ${seconds / 3600}h`;
  if (seconds % 60 === 0) return `every ${seconds / 60}m`;
  return `every ${seconds}s`;
}

export function parseSchedule(plist: Plist): Schedule {
  const rawCalendar = plist.StartCalendarInterval;
  const calendar = (Array.isArray(rawCalendar) ? rawCalendar : rawCalendar ? [rawCalendar] : []) as CalendarEntry[];
  const interval = typeof plist.StartInterval === "number" ? plist.StartInterval : undefined;
  // KeepAlive may be a bool or a dict of conditions; either way launchd restarts the job.
  const keepAlive = plist.KeepAlive === true || (typeof plist.KeepAlive === "object" && plist.KeepAlive !== null);
  const runAtLoad = plist.RunAtLoad === true;
  const watchPaths = Array.isArray(plist.WatchPaths) ? (plist.WatchPaths as string[]) : [];

  const parts: string[] = [];
  if (keepAlive) parts.push("always on");
  if (interval !== undefined) parts.push(describeInterval(interval));
  for (const entry of calendar) parts.push(describeCalendar(entry));
  if (watchPaths.length > 0) parts.push(`on change of ${watchPaths.length} path${watchPaths.length > 1 ? "s" : ""}`);
  if (runAtLoad && !keepAlive) parts.push(parts.length > 0 ? "and at login" : "once at login");
  if (parts.length === 0) parts.push("on demand");

  return { keepAlive, runAtLoad, interval, calendar, watchPaths, summary: parts.join(", ") };
}

function matchesCalendar(date: Date, entry: CalendarEntry): boolean {
  return (
    (entry.Minute ?? 0) === date.getMinutes() &&
    (entry.Hour === undefined || entry.Hour === date.getHours()) &&
    (entry.Day === undefined || entry.Day === date.getDate()) &&
    (entry.Month === undefined || entry.Month === date.getMonth() + 1) &&
    (entry.Weekday === undefined || entry.Weekday % 7 === date.getDay())
  );
}

// Minute-by-minute scan is fine: at most one year of minutes, and only for calendar jobs.
export function nextCalendarRun(entries: CalendarEntry[], from: Date): Date | undefined {
  const cursor = new Date(from);
  cursor.setSeconds(0, 0);
  for (let i = 0; i < 366 * 24 * 60; i++) {
    cursor.setMinutes(cursor.getMinutes() + 1);
    if (entries.some((entry) => matchesCalendar(cursor, entry))) return new Date(cursor);
  }
  return undefined;
}

export function parseLaunchctlPrint(output: string): LiveState {
  // Nested blocks repeat keys like `state = active`; only the top-level (single-tab) lines describe the job.
  const top = new Map<string, string>();
  for (const line of output.split("\n")) {
    const match = /^\t([a-z][a-z ]*?) = (.*)$/.exec(line);
    if (match && !top.has(match[1])) top.set(match[1], match[2]);
  }
  const num = (key: string) => (top.has(key) ? Number(top.get(key)) : undefined);
  const signal = top.get("last terminating signal");
  const lastExit = top.get("last exit code") ?? (signal ? `signal: ${signal}` : undefined);
  return { loaded: true, state: top.get("state"), pid: num("pid"), runs: num("runs"), lastExit };
}

// undefined = nothing to judge: never exited, or stopped by SIGTERM (launchctl bootout, restarts).
export function isSuccessfulExit(lastExit: string | undefined): boolean | undefined {
  if (lastExit === undefined || lastExit.startsWith("(never")) return undefined;
  if (lastExit === "143" || lastExit.endsWith(": 15")) return undefined;
  return lastExit === "0";
}

// ---------------------------------------------------------------------------- #
//                                    SOURCES                                   #
// ---------------------------------------------------------------------------- #

function readPlist(file: string): { plist: Plist; error?: string } {
  const proc = Bun.spawnSync(["/usr/bin/plutil", "-convert", "json", "-o", "-", file]);
  if (proc.exitCode !== 0) return { plist: {}, error: proc.stderr.toString().trim() || "plutil failed" };
  try {
    return { plist: JSON.parse(proc.stdout.toString()) as Plist };
  } catch (error) {
    return { plist: {}, error: String(error) };
  }
}

function readLiveState(label: string): LiveState {
  const proc = Bun.spawnSync(["/bin/launchctl", "print", `gui/${process.getuid?.()}/${label}`]);
  if (proc.exitCode !== 0) return { loaded: false };
  return parseLaunchctlPrint(proc.stdout.toString());
}

async function readLogTail(file: string) {
  if (!existsSync(file)) return { path: file, exists: false, lines: [] as string[], errorLines: 0 };
  const { size, mtime } = statSync(file);
  const start = Math.max(0, size - LOG_TAIL_BYTES);
  const lines = (await Bun.file(file).slice(start, size).text()).split("\n");
  if (start > 0) lines.shift(); // drop the partial first line
  if (lines.at(-1) === "") lines.pop();
  const tail = lines.slice(-LOG_TAIL_LINES);
  return {
    path: file,
    exists: true,
    size,
    mtime: mtime.toISOString(),
    lines: tail,
    errorLines: tail.filter((line) => ERROR_PATTERN.test(line)).length,
  };
}

// Some agents redirect inside an inline shell script (`exec >>"$dir/agent.log" 2>&1`) instead of using
// StandardOutPath; resolve simple `var="..."` assignments plus $HOME and XDG_STATE_HOME to find those logs.
export function scriptLogPaths(script: string, home: string, stateHome: string): string[] {
  const vars = new Map<string, string>();
  const expand = (value: string) =>
    value
      .replaceAll("${XDG_STATE_HOME:-$HOME/.local/state}", stateHome)
      .replace(/\$\{?(\w+)\}?/g, (whole, name: string) => (name === "HOME" ? home : (vars.get(name) ?? whole)));
  const paths: string[] = [];
  for (const line of script.split("\n")) {
    const assignment = /^\s*(\w+)="([^"]*)"\s*$/.exec(line);
    if (assignment) vars.set(assignment[1], expand(assignment[2]));
    const redirect = /\bexec\s+>>?\s*"([^"]+)"/.exec(line);
    if (redirect) paths.push(expand(redirect[1]));
  }
  return paths.filter((path) => path.startsWith("/") && !path.includes("$"));
}

export function logPaths(plist: Plist, home = HOME, stateHome = STATE_HOME): string[] {
  const paths = [plist.StandardOutPath, plist.StandardErrorPath].filter((p): p is string => typeof p === "string");
  const args = Array.isArray(plist.ProgramArguments) ? (plist.ProgramArguments as string[]) : [];
  for (const arg of args) paths.push(...scriptLogPaths(arg, home, stateHome));
  return [...new Set(paths)];
}

function listAgentFiles(): string[] {
  if (!existsSync(AGENTS_DIR)) return [];
  return readdirSync(AGENTS_DIR)
    .filter((name) => name.endsWith(".plist"))
    .sort();
}

function isChezmoiManaged(file: string): boolean {
  return existsSync(join(CHEZMOI_AGENTS_DIR, file)) || existsSync(join(CHEZMOI_AGENTS_DIR, `${file}.tmpl`));
}

function loadAgents() {
  return listAgentFiles()
    .map((file) => {
      const path = join(AGENTS_DIR, file);
      const { plist, error } = readPlist(path);
      const label = typeof plist.Label === "string" ? plist.Label : basename(file, ".plist");
      return { file, path, label, plist, error };
    })
    .filter((agent) => agent.label !== SELF_LABEL);
}

// ---------------------------------------------------------------------------- #
//                                    HISTORY                                   #
// ---------------------------------------------------------------------------- #

let history: HistoryEvent[] = [];
const lastSeen = new Map<string, LiveState>();

function loadHistory() {
  if (!existsSync(HISTORY_FILE)) return;
  history = readFileSync(HISTORY_FILE, "utf8")
    .split("\n")
    .filter(Boolean)
    .flatMap((line) => {
      try {
        return [JSON.parse(line) as HistoryEvent];
      } catch {
        return [];
      }
    })
    .slice(-HISTORY_LIMIT);
}

function record(event: HistoryEvent) {
  history.push(event);
  if (history.length > HISTORY_LIMIT) history = history.slice(-HISTORY_LIMIT);
  mkdirSync(dirname(HISTORY_FILE), { recursive: true });
  appendFileSync(HISTORY_FILE, `${JSON.stringify(event)}\n`);
}

// Compare two samples of one job and derive the run/exit events that happened in between.
export function diffSamples(label: string, prev: LiveState | undefined, next: LiveState, ts: string): HistoryEvent[] {
  if (!prev || !next.loaded || !prev.loaded) return [];
  const events: HistoryEvent[] = [];
  const newRuns = (next.runs ?? 0) - (prev.runs ?? 0);
  const pidChanged = next.pid !== undefined && next.pid !== prev.pid;
  if (newRuns > 0 || pidChanged) {
    // A short job can start and exit between samples; record each start, then its exit.
    const starts = Math.max(newRuns, 1);
    for (let i = 0; i < starts; i++) {
      events.push({ ts, label, kind: "start", pid: i === starts - 1 ? next.pid : undefined });
      const finished = i < starts - 1 || next.pid === undefined;
      if (finished) events.push({ ts, label, kind: "exit", exit: next.lastExit });
    }
  } else if (prev.pid !== undefined && next.pid === undefined) {
    events.push({ ts, label, kind: "exit", pid: prev.pid, exit: next.lastExit });
  }
  return events;
}

function sample() {
  const ts = new Date().toISOString();
  for (const agent of loadAgents()) {
    const next = readLiveState(agent.label);
    for (const event of diffSamples(agent.label, lastSeen.get(agent.label), next, ts)) record(event);
    lastSeen.set(agent.label, next);
  }
}

// ---------------------------------------------------------------------------- #
//                                    UPTIME                                    #
// ---------------------------------------------------------------------------- #

// Parse ps `etime` ([[dd-]hh:]mm:ss) into seconds.
export function parseElapsed(etime: string): number | undefined {
  const match = /^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$/.exec(etime.trim());
  if (!match) return undefined;
  const [, days = "0", hours = "0", minutes, seconds] = match;
  return ((Number(days) * 24 + Number(hours)) * 60 + Number(minutes)) * 60 + Number(seconds);
}

// One ps call for all running jobs; returns pid -> process start time.
function readStartTimes(pids: number[], now: Date): Map<number, string> {
  const startedAt = new Map<number, string>();
  if (pids.length === 0) return startedAt;
  const proc = Bun.spawnSync(["/bin/ps", "-o", "pid=,etime=", "-p", pids.join(",")]);
  for (const line of proc.stdout.toString().split("\n")) {
    const [pid, etime] = line.trim().split(/\s+/);
    const elapsed = etime ? parseElapsed(etime) : undefined;
    if (elapsed !== undefined) startedAt.set(Number(pid), new Date(now.getTime() - elapsed * 1000).toISOString());
  }
  return startedAt;
}

// ---------------------------------------------------------------------------- #
//                                     API                                      #
// ---------------------------------------------------------------------------- #

async function agentsPayload() {
  const now = new Date();
  const loaded = loadAgents().map((agent) => ({
    ...agent,
    live: lastSeen.get(agent.label) ?? readLiveState(agent.label),
  }));
  const startTimes = readStartTimes(
    loaded.flatMap((agent) => (agent.live.pid === undefined ? [] : [agent.live.pid])),
    now,
  );
  const agents = await Promise.all(
    loaded.map(async (agent) => {
      const schedule = parseSchedule(agent.plist);
      const live = agent.live;
      const logs = await Promise.all(logPaths(agent.plist).map(readLogTail));
      const args = Array.isArray(agent.plist.ProgramArguments)
        ? (agent.plist.ProgramArguments as string[])
        : typeof agent.plist.Program === "string"
          ? [agent.plist.Program]
          : [];
      const lastLogWrite = logs
        .map((log) => log.mtime)
        .filter(Boolean)
        .sort()
        .at(-1);
      let nextRun: string | undefined;
      if (schedule.calendar.length > 0) nextRun = nextCalendarRun(schedule.calendar, now)?.toISOString();
      return {
        label: agent.label,
        ...describeAgent(agent.label),
        file: agent.file,
        path: agent.path,
        managed: isChezmoiManaged(agent.file),
        plistError: agent.error,
        schedule,
        live,
        startedAt: live.pid === undefined ? undefined : startTimes.get(live.pid),
        lastExitOk: isSuccessfulExit(live.lastExit),
        nextRun,
        lastLogWrite,
        program: args,
        workingDirectory: agent.plist.WorkingDirectory,
        logs,
        history: history.filter((event) => event.label === agent.label).slice(-50),
      };
    }),
  );
  agents.sort(
    (a, b) =>
      GROUPS.indexOf(a.group) - GROUPS.indexOf(b.group) ||
      Number(b.managed) - Number(a.managed) ||
      a.name.localeCompare(b.name),
  );
  return { generatedAt: now.toISOString(), sampleSeconds: SAMPLE_MS / 1000, historyFile: HISTORY_FILE, agents };
}

// DNS-rebinding guard: only the named HTTPS host (via Caddy) and direct loopback may reach the app.
export function isAllowedHost(host: string | null): boolean {
  return host !== null && ALLOWED_HOSTS.has(host.toLowerCase());
}

const indexHtml = Bun.file(join(import.meta.dir, "index.html"));

export async function handle(request: Request): Promise<Response> {
  if (!isAllowedHost(request.headers.get("host"))) return new Response("Forbidden host", { status: 403 });
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  const { pathname } = new URL(request.url);
  if (pathname === "/") return new Response(indexHtml, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  if (pathname === "/api/agents")
    return Response.json(await agentsPayload(), { headers: { "Cache-Control": "no-store" } });
  return new Response("Not found", { status: 404 });
}

if (import.meta.main) {
  loadHistory();
  sample();
  setInterval(sample, SAMPLE_MS);
  Bun.serve({ hostname: "127.0.0.1", port: PORT, fetch: handle });
  console.log(`launchd dashboard listening on http://127.0.0.1:${PORT} (https://launchd.localhost)`);
}
