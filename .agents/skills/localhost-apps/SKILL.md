---
argument-hint: "<list|add|remove> [app-name]"
compatibility: Requires macOS, chezmoi, Caddy, launchd, Bun, and this dotfiles repository.
name: localhost-apps
description:
  Add, remove, or list permanent Caddy-based named localhost apps backed by macOS LaunchAgents. Use for always-on local
  servers, *.localhost proxies, Caddy routes, or launchd-managed development apps on this machine.
---

# Permanent Localhost Apps

Manage named HTTPS localhost proxies and the macOS LaunchAgents that keep their upstream apps running.

## Arguments

- `list` or no arguments: Show every permanent localhost app and its live health.
- `add <app-name>`: Add `<app-name>.localhost`, its upstream port, and its always-on service.
- `remove <app-name>`: Remove the proxy and service after explicit confirmation.

Use an explicit user-supplied hostname, port, label, source path, or command when provided. Otherwise derive them from
repository evidence and the conventions below.

## Invariants

- A permanent app has both a Caddy route in `dot_config/caddy/Caddyfile` and a matching `KeepAlive` LaunchAgent under
  `Library/LaunchAgents/`.
- Bind app servers to `127.0.0.1`; expose them through `https://<name>.localhost`, never a LAN interface.
- Treat proxy compatibility as an application invariant: its framework, server, API, same-origin, CSRF, and host checks
  must accept the exact named HTTPS origin without broadening trust to arbitrary `.localhost` hosts or forwarded
  headers.
- Give every service a distinct label, port, working directory, and log under `~/Library/Logs/`.
- Keep the app repository and its data intact when removing a proxy unless the user separately asks to delete them.
- Follow the coordination, validation, commit, push, and scoped-apply rules in `AGENTS.md` for every affected
  repository.
- Treat `list` as read-only. Adding writes repository and live launchd state. Removing is destructive and requires
  confirmation after the exact removal set is known.

## List

Run:

```sh
bun run .agents/skills/localhost-apps/scripts/list.ts
```

Relay its Markdown table without restating healthy rows. Investigate any missing metadata, unloaded service, failed
listener, or non-successful HTTPS response before claiming the inventory is healthy.

### Helper interface

`scripts/list.ts` accepts no arguments. Run it with `bun run .agents/skills/localhost-apps/scripts/list.ts` from the
repository. It reads the Caddyfile and matching plist templates, queries launchd, probes HTTPS, prints a Markdown table
to stdout, and exits nonzero only when repository metadata cannot be read or parsed. An unhealthy service remains a
successful inventory result and is marked in the table.

## Add

1. Inspect the app repository's instructions, manifest, launch command, bind address, existing port, and durable docs.
   Inspect the nearest analogous Caddy block, LaunchAgent plist, and reload hook in this repository.
2. Resolve the hostname, source directory, launch command, service label, log path, and port. Preserve a safe existing
   port unless the user requested a change; otherwise choose a random free port in `8000-8999` that is absent from the
   Caddyfile, the app repository, and `lsof -nP -iTCP -sTCP:LISTEN`.
3. Identify every write target, then acquire exact `ai-coord` scopes in each Git repository before editing. A normal add
   changes:
   - the app's bind/port configuration and its AGENTS/README guidance;
   - `dot_config/caddy/Caddyfile`;
   - `Library/LaunchAgents/<label>.plist.tmpl`;
   - `dot_setup/run_onchange_after_setup_<slug>_macos.sh.tmpl`;
   - this repository's local-HTTPS guidance in `AGENTS.md`.
4. Configure the app to bind strictly to `127.0.0.1:<port>`. Preserve its established development or production command;
   do not invent a build/deployment layer merely to daemonize it.
5. Trace every framework allowlist and server-side `Host`, `Origin`, same-origin, or CSRF check used by browser and API
   requests. Where enforcement exists, allow exactly `<name>.localhost` and its default-TLS form `<name>.localhost:443`,
   with expected origin `https://<name>.localhost`; retain required direct-loopback access. Never authorize wildcard
   `.localhost` subdomains, attacker suffixes, non-default ports, or `X-Forwarded-*` headers.
6. Add a Caddy block with comments naming the app, source directory, and LaunchAgent. Proxy to `127.0.0.1:<port>`.
7. Add a plist following the closest existing service. Include `KeepAlive`, `RunAtLoad`, `ProcessType`,
   `WorkingDirectory`, explicit program arguments, stdout/stderr log paths, and only the PATH entries the command needs.
8. Add a `run_onchange_after_setup_*_macos.sh.tmpl` hook following an existing reload hook. Include the plist's hash so
   changes retrigger it; validate the rendered plist, boot out an old instance, bootstrap with the established retry,
   and prove launchd loaded the label.
9. Update durable instructions so users and agents open the named HTTPS URL and do not start a competing server on the
   default port. Document the service label, log, and restart command.
10. Add proxy regression coverage for the real browser path. For an app with an API, test a read and a representative
    state-changing request using the named `Host` and exact HTTPS `Origin`, plus rejection of sibling hosts, attacker
    suffixes, wrong schemes/ports, and forwarded-header impersonation. A successful HTML shell response is not proof
    that the proxied app works.
11. Run the narrow app checks plus this repository's `just full-check`, `caddy validate`, and
    `gitleaks git --redact --no-banner --no-color`. Format only owned files.
12. Commit and push each coherent repository change under its local rules. Authenticate 1Password, apply chezmoi using
    the repository's changed-file count rule, and include Caddy's hash-triggered hook whenever the Caddyfile changed.
13. Verify the LaunchAgent is running and the chosen port is listening. Exercise the named HTTPS page and its critical
    proxied API read/write flow without a manually started process; do not stop at `curl` of `/`. Check the system
    keychain for `Caddy Local Authority`; if absent, tell the user to run `caddy trust` rather than invoking its sudo
    prompt yourself.

## Remove

1. Run the inventory and resolve the exact Caddy block, service label, plist source, reload hook, installed plist,
   documentation references, listener, and app repository. State that the app repository and data will remain.
2. Ask for confirmation to unload the service and delete the managed proxy/service files. Do not mutate state before
   confirmation.
3. After confirmation, acquire exact `ai-coord` scopes. Boot out `gui/$(id -u)/<label>`, remove the Caddy block, source
   plist, and reload hook, and update durable docs.
4. Add `Library/LaunchAgents/<label>.plist` to `.chezmoiremove` with a concise reason. This is required so other
   machines delete the formerly managed target after pulling the source deletion; deleting only the source leaves an
   orphan.
5. Leave the app's repository, data, dependencies, and port configuration unchanged unless the user explicitly expands
   scope. Remove only instructions that falsely claim the permanent service still exists.
6. Validate the remaining Caddyfile, plist/templates, shell, docs, and repository checks; commit and push coherent
   changes; then authenticate and apply chezmoi.
7. Verify launchd no longer knows the label, the old port has no listener from that service, the removed hostname is no
   longer routed, and the inventory table no longer contains the app.

## Completion

- For `list`, return the helper's table and only the evidence needed to explain unhealthy rows.
- For `add` or `remove`, lead with the resulting URL/service state, then report the label, port, source, log,
  validation, pushed commits, apply result, and whether the user must run `caddy trust`.
