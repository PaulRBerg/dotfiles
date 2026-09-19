#!/usr/bin/env bun

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

type Route = {
  backend: string;
  hostname: string;
  label: string;
  log: string;
  source: string;
};

const decoder = new TextDecoder();
const repoRoot = resolve(import.meta.dir, "../../../..");
const caddyfile = resolve(repoRoot, "dot_config/caddy/Caddyfile");

if (!existsSync(caddyfile)) {
  console.error(`missing Caddyfile: ${caddyfile}`);
  process.exit(1);
}

const normalizeHome = (value: string): string => value.replaceAll("{{ .chezmoi.homeDir }}", "~");

const plistString = (plist: string, key: string): string | undefined => {
  const match = plist.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`));
  return match?.[1];
};

const routes: Route[] = [];
const lines = readFileSync(caddyfile, "utf8").split("\n");

for (let index = 0; index < lines.length; index += 1) {
  const block = lines[index]?.match(/^([a-z0-9.-]+\.localhost)\s+\{$/);
  if (!block) continue;

  const comments: string[] = [];
  for (let cursor = index - 1; cursor >= 0 && lines[cursor]?.startsWith("#"); cursor -= 1) {
    comments.unshift(lines[cursor] ?? "");
  }

  const metadata = comments.join("\n").match(/# Source:\s*([^,]+), served by the ([a-z0-9._-]+) LaunchAgent\./i);
  if (!metadata) continue;

  let backend: string | undefined;
  for (let cursor = index + 1; cursor < lines.length && lines[cursor] !== "}"; cursor += 1) {
    backend = lines[cursor]?.match(/^\s*reverse_proxy\s+(127\.0\.0\.1:\d+)\s*$/)?.[1] ?? backend;
  }
  if (!backend) {
    console.error(`missing loopback reverse_proxy for ${block[1]}`);
    process.exit(1);
  }

  const label = metadata[2] ?? "";
  const plistPath = resolve(repoRoot, `Library/LaunchAgents/${label}.plist.tmpl`);
  if (!existsSync(plistPath)) continue;

  const plist = readFileSync(plistPath, "utf8");
  if (!/<key>KeepAlive<\/key>\s*<true\s*\/>/.test(plist)) continue;

  routes.push({
    backend,
    hostname: block[1] ?? "",
    label,
    log: normalizeHome(plistString(plist, "StandardErrorPath") ?? "—"),
    source: metadata[1] ?? normalizeHome(plistString(plist, "WorkingDirectory") ?? "—"),
  });
}

const title = (hostname: string): string =>
  hostname
    .replace(/\.localhost$/, "")
    .split(/[.-]/)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");

const launchdState = (label: string): string => {
  const uid = process.getuid?.();
  if (uid === undefined) return "⚪ unavailable";

  const result = Bun.spawnSync({
    cmd: ["launchctl", "print", `gui/${uid}/${label}`],
    stderr: "ignore",
    stdout: "pipe",
  });
  if (result.exitCode !== 0) return "⚪ unloaded";

  const state = decoder.decode(result.stdout).match(/^\s*state = (\S+)$/m)?.[1] ?? "loaded";
  return state === "running" ? "🟢 running" : `🟡 ${state}`;
};

const httpsState = (hostname: string): string => {
  const result = Bun.spawnSync({
    cmd: [
      "curl",
      "--silent",
      "--show-error",
      "--output",
      "/dev/null",
      "--write-out",
      "%{http_code}",
      "--connect-timeout",
      "1",
      "--max-time",
      "3",
      `https://${hostname}/`,
    ],
    stderr: "ignore",
    stdout: "pipe",
  });
  if (result.exitCode !== 0) return "❌ unavailable";

  const code = decoder.decode(result.stdout).trim();
  return /^[23]\d\d$/.test(code) ? `✅ ${code}` : `⚠️ ${code}`;
};

routes.sort((left, right) => left.hostname.localeCompare(right.hostname));

console.log("### Permanent localhost apps\n");
if (routes.length === 0) {
  console.log("_No permanent localhost apps found._");
  process.exit(0);
}

console.log("| App | URL | Backend | LaunchAgent | State | HTTPS | Source | Log |");
console.log("| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |");
for (const route of routes) {
  console.log(
    `| ${title(route.hostname)} | [${route.hostname}](https://${route.hostname}) | \`${route.backend}\` | \`${route.label}\` | ${launchdState(route.label)} | ${httpsState(route.hostname)} | \`${route.source}\` | \`${route.log}\` |`,
  );
}
