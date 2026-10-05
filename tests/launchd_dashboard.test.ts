import { describe, expect, test } from "bun:test";

import {
  diffSamples,
  handle,
  isAllowedHost,
  isSuccessfulExit,
  logPaths,
  nextCalendarRun,
  parseLaunchctlPrint,
  parseSchedule,
} from "../dot_config/launchd-dashboard/server.ts";

describe("parseSchedule", () => {
  test("summarizes keep-alive, interval, calendar, and login triggers", () => {
    expect(parseSchedule({ KeepAlive: true, RunAtLoad: true }).summary).toBe("always on");
    expect(parseSchedule({ StartInterval: 3600, RunAtLoad: true }).summary).toBe("every 1h, and at login");
    expect(parseSchedule({ StartCalendarInterval: { Hour: 9, Minute: 0 } }).summary).toBe("daily at 09:00");
    expect(parseSchedule({ StartCalendarInterval: [{ Minute: 30 }, { Weekday: 1, Hour: 7 }] }).summary).toBe(
      "hourly at :30, at 07:00 on Mon",
    );
    expect(parseSchedule({ RunAtLoad: true }).summary).toBe("once at login");
    expect(parseSchedule({}).summary).toBe("on demand");
  });
});

describe("nextCalendarRun", () => {
  test("finds the next matching minute in local time", () => {
    const from = new Date(2026, 9, 5, 10, 15);
    expect(nextCalendarRun([{ Hour: 9, Minute: 0 }], from)).toEqual(new Date(2026, 9, 6, 9, 0));
    expect(nextCalendarRun([{ Minute: 30 }], from)).toEqual(new Date(2026, 9, 5, 10, 30));
    expect(nextCalendarRun([{ Weekday: 0, Hour: 8 }], from)).toEqual(new Date(2026, 9, 11, 8, 0));
  });
});

describe("parseLaunchctlPrint", () => {
  test("reads top-level fields and ignores nested blocks", () => {
    const output = [
      "gui/501/local.x = {",
      "\tstate = running",
      "\tevent channels = {",
      "\t\tstate = active",
      "\t}",
      "\truns = 3",
      "\tpid = 42",
      "\tlast terminating signal = Terminated: 15",
      "}",
    ].join("\n");
    expect(parseLaunchctlPrint(output)).toEqual({
      loaded: true,
      state: "running",
      pid: 42,
      runs: 3,
      lastExit: "signal: Terminated: 15",
    });
  });

  test("classifies exits", () => {
    expect(isSuccessfulExit("0")).toBe(true);
    expect(isSuccessfulExit("1")).toBe(false);
    expect(isSuccessfulExit("143")).toBeUndefined();
    expect(isSuccessfulExit("(never exited)")).toBeUndefined();
  });
});

describe("diffSamples", () => {
  const ts = "2026-10-05T09:00:00.000Z";

  test("records a short job that ran entirely between samples", () => {
    const prev = { loaded: true, runs: 4, lastExit: "0" };
    const next = { loaded: true, runs: 5, lastExit: "2" };
    expect(diffSamples("x", prev, next, ts)).toEqual([
      { ts, label: "x", kind: "start", pid: undefined },
      { ts, label: "x", kind: "exit", exit: "2" },
    ]);
  });

  test("records start and exit of a long-running process separately", () => {
    const idle = { loaded: true, runs: 1, lastExit: "0" };
    const running = { loaded: true, runs: 2, pid: 7, lastExit: "0" };
    expect(diffSamples("x", idle, running, ts)).toEqual([{ ts, label: "x", kind: "start", pid: 7 }]);
    expect(diffSamples("x", running, { ...idle, runs: 2, lastExit: "1" }, ts)).toEqual([
      { ts, label: "x", kind: "exit", pid: 7, exit: "1" },
    ]);
  });

  test("records nothing on the first sample or without change", () => {
    const state = { loaded: true, runs: 1, pid: 7 };
    expect(diffSamples("x", undefined, state, ts)).toEqual([]);
    expect(diffSamples("x", state, state, ts)).toEqual([]);
  });
});

describe("logPaths", () => {
  test("combines plist paths with script redirects", () => {
    const plist = {
      StandardOutPath: "/h/Library/Logs/a.log",
      StandardErrorPath: "/h/Library/Logs/a.log",
      ProgramArguments: [
        "/bin/bash",
        "-c",
        'state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/mon"\nexec >>"$state_dir/agent.log" 2>&1\nexec >>"$UNKNOWN/x.log"',
      ],
    };
    expect(logPaths(plist, "/h", "/h/.local/state")).toEqual([
      "/h/Library/Logs/a.log",
      "/h/.local/state/mon/agent.log",
    ]);
  });
});

describe("host guard (proxy path)", () => {
  const get = (host: string, path = "/api/agents", headers: Record<string, string> = {}) =>
    handle(new Request(`http://127.0.0.1:8479${path}`, { headers: { host, ...headers } }));

  test("accepts the named HTTPS host and direct loopback", () => {
    for (const host of [
      "launchd.localhost",
      "launchd.localhost:443",
      "LAUNCHD.localhost",
      "127.0.0.1:8479",
      "localhost:8479",
    ]) {
      expect(isAllowedHost(host)).toBe(true);
    }
  });

  test("rejects siblings, suffixes, and wrong ports", () => {
    for (const host of [
      "budget.localhost",
      "x.launchd.localhost",
      "launchd.localhost.evil.com",
      "launchd.localhost:8443",
      "evil.com",
      "127.0.0.1:80",
    ]) {
      expect(isAllowedHost(host)).toBe(false);
    }
  });

  test("ignores forwarded-host impersonation", async () => {
    const response = await get("evil.com", "/", { "x-forwarded-host": "launchd.localhost" });
    expect(response.status).toBe(403);
  });

  test("reads live agents through the named host", async () => {
    const response = await get("launchd.localhost");
    expect(response.status).toBe(200);
    const body = (await response.json()) as { agents: { label: string }[] };
    expect(Array.isArray(body.agents)).toBe(true);
  });

  test("serves the page through the named host and refuses writes", async () => {
    const page = await get("launchd.localhost", "/");
    expect(page.status).toBe(200);
    expect(await page.text()).toContain("<title>LaunchAgents</title>");
    const write = await handle(
      new Request("http://127.0.0.1:8479/api/agents", {
        method: "POST",
        headers: { host: "launchd.localhost", origin: "https://launchd.localhost" },
      }),
    );
    expect(write.status).toBe(405);
  });
});
