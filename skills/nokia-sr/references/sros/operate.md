# SR OS NETCONF & MD-CLI behaviors

SR OS deviates from textbook NETCONF in ways that cause silent failures if ignored.

## Configuration mode (device-wide): classic / mixed / model-driven

Before anything else, know which configuration mode the box is in - it decides whether MD-CLI / NETCONF candidate editing is even available. It is a system-wide setting, distinct from the per-session candidate modes below.

| Mode | Who can configure | NETCONF / MD-CLI candidate |
|------|-------------------|----------------------------|
| `classic` | Classic CLI only | Not available - NETCONF config edits are rejected |
| `mixed` | Classic CLI **and** MD-CLI / NETCONF | Available, but coexists with classic; expect the `lock` caveat below |
| `model-driven` | MD-CLI / NETCONF / gNMI only (classic config disabled) | Full candidate workflow |

The config leaf is `configure system management-interface configuration-mode`. Switching between `classic` and `model-driven` requires a reboot.

**Detect it:**

- MD-CLI: from `configure system management-interface`, run `info` and read the `configuration-mode` line. Reliable and version-independent.
- From a saved config: `grep -n 'configuration-mode' <file>`.
- NETCONF: `<get-config>` the same path. The exact state/config YANG path is version-dependent - verify it against the pinned models (`grep -rn 'configuration-mode' "$YANG/YANG/nokia-combined/nokia-conf.yang"`) rather than hardcoding it. See `version-detection.md` and `../global/yang-models.md`.
- Prompt heuristic (interactive only, not authoritative): model-driven MD-CLI shows a `[/...]` context line above the `A:admin@node#` prompt; classic CLI shows `*A:node#` with no context line.

If the device is in `classic` mode, stop expecting NETCONF candidate edits to work - switch the box (and reboot) or drive it over classic CLI instead.

## NETCONF quirks

- **`<default-operation>` is ignored.** SR OS does not honour it in `<edit-config>`. Set the operation explicitly with `nc:operation` on the `<configure>` root or the relevant element instead.

- **Operation placement matters.** Put `nc:operation="replace"` on the smallest container or leaf that must change - never on a shared parent that aggregates entries from multiple services, or you wipe the siblings. Full-subtree replace example:

  ```xml
  <configure
    xmlns="urn:nokia.com:sros:ns:yang:sr:conf"
    xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0"
    nc:operation="replace">
    <!-- subtree -->
  </configure>
  ```

- **Error handling:** `stop-on-error` and `rollback-on-error` are supported and both trigger a full rollback. `continue-on-error` is NOT supported and raises an RPC error.

- **Mixed-mode devices (classic CLI + MD-CLI):** `lock`/`unlock` on the `candidate` datastore raises an `RPCError`. Catch and tolerate it with a warning; do not abort.

- **Commit with comment** requires the device to advertise `urn:nokia.com:sros:ns:yang:sr:ietf-netconf-augments`. Check `server_capabilities` first, then dispatch:

  ```xml
  <commit xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
    <comment>your comment here</comment>
  </commit>
  ```

## md-compare (SR OS >= 22)

A Nokia action that diffs candidate vs running in MD-CLI format - a human-readable pre-commit diff:

```xml
<action xmlns="urn:nokia.com:sros:ns:yang:sr:conf">
  <md-compare/>
</action>
```

Falls back to SSH CLI `compare` on older releases or when the MD-CLI engine is unavailable.

## MD-CLI candidate modes (per session)

Distinct from the device-wide configuration-mode above: each MD-CLI session picks how it edits the candidate.

| Command | Candidate | Use when |
|---------|-----------|----------|
| `configure global` (or plain `configure`) | Shared global candidate - concurrent editors see each other's uncommitted changes | Default; coordinated single-operator work |
| `configure exclusive` | Locks the global candidate so no one else can enter `configure` | You must guarantee no concurrent edits |
| `configure private` | Private candidate isolated until `commit`; conflicts detected at commit | Multiple operators editing different services in parallel |
| `configure read-only` | View only, cannot edit | Inspect candidate without risk of changing it |

NETCONF sessions edit a per-session private candidate, which is why two services committed independently do not clobber each other - but it also means an uncommitted change in one session is invisible to another.

## MD-CLI navigation and commit basics

- `configure [global|exclusive|private|read-only]` enters candidate config; `exit all` returns to the root.
- `info` / `info flat` / `info json` show the current context (see `config-format.md`).
- `pwc` prints the current working context path.
- `compare` shows candidate vs running; `validate` checks the candidate without applying it; `discard` drops candidate changes.
- `logout` ends the session and disconnects (use `exit all` first if you only mean to leave the config context, not the device). Discard or commit any candidate changes before logging out.

### Compare before you commit

Always review the candidate before committing, and propose this to the user first: run `compare` (or the `md-compare` action over NETCONF, see above) to show exactly what will change versus running, and `validate` to check it applies cleanly. Only commit once the diff is confirmed.

### Commit safety variants

- `commit` - apply the candidate.
- `commit comment "text"` - apply and attach a comment to the rollback/log entry (audit trail). Over NETCONF this needs the `ietf-netconf-augments` capability (see NETCONF quirks above).
- `commit confirmed [<minutes>]` - apply, but auto-rollback after the timeout unless a follow-up `commit` confirms it within the window. Essential for remote changes that could cut your own management path: if the change locks you out, the box reverts itself.

## Reference

Nokia SR OS NETCONF guide: <https://documentation.nokia.com/sr/> (System Management > NETCONF).
