# Operating SR Linux (gNMI / JSON-RPC / NETCONF / CLI)

SR Linux exposes the same YANG model over several management interfaces. Pick by tooling; all act on the same datastores.

## Datastores

| Datastore | Purpose |
|-----------|---------|
| `running` | active committed config |
| `candidate` | editable copy; changes apply on `commit` |
| `state` | operational state (config + read-only state) |
| `tools` | imperative operational actions (clear, reset, ...) |

## CLI candidate workflow (`sr_cli`)

```
enter candidate            # open a candidate (shared by default; 'private' for isolation)
  set / interface ethernet-1/1 admin-state enable
  commit now               # apply and exit candidate
```

**`commit` exists only inside candidate mode.** In the default (running/show) context there is no `commit` command - the parser won't recognize it. You must `enter candidate` first; trying to commit from the top level is a common mistake.

**Discover and self-verify commands with `?`.** Append `?` (or type any unknown token) and SR Linux prints the exact valid next tokens for your release - e.g. `commit ?` lists `now stay save confirmed validate checkpoint`, `save ?` lists `checkpoint file rescue startup`. Use this to confirm a command exists on the target box instead of guessing.

The full `commit` set inside candidate mode is `now`, `stay`, `save`, `confirmed`, `validate`, `checkpoint`:

- `commit now` - apply and leave the candidate.
- `commit stay` - apply but keep editing.
- `commit save` - apply, and also save to the startup config.
- `commit confirmed [<timeout>]` - apply, auto-revert unless confirmed within the window. Use for remote changes that could cut your own management path.
- `commit validate` - check the candidate applies cleanly without committing it.
- `discard now` - drop candidate changes and leave the candidate.
- `diff` - show the candidate vs running diff.
- `save startup` - standalone command to persist the running config across reboot.

### Compare before you commit

Always review the candidate before committing, and propose this to the user first: run `diff` to show exactly what will change versus the running config, and `commit validate` to check it applies cleanly. Only commit once the diff is confirmed.

## gNMI (native)

SR Linux is gNMI-first. Use `gnmic`:

```bash
gnmic -a <node>:57400 -u admin -p <pw> --skip-verify \
  get --path /interface[name=ethernet-1/1]/admin-state --encoding json_ietf
gnmic -a <node>:57400 ... set --update-path /interface[name=ethernet-1/1]/admin-state \
  --update-value enable
```

Paths come straight from the `srl_nokia-*` models (`../global/yang-models.md`). Default encoding is `json_ietf`. gNMI Subscribe streams state for telemetry.

## JSON-RPC

POST to `https://<node>/jsonrpc` (and `/jsonrpc/cli`). Methods: `get`, `set`, `validate`, `cli`, `diff`. Each operation names a `datastore` (`running` / `candidate` / `state` / `tools`) and a list of `path` + `value` commands. Example body:

```json
{ "jsonrpc": "2.0", "id": 1, "method": "get",
  "params": { "datastore": "state",
              "commands": [ { "path": "/system/information/version" } ] } }
```

`set` against `candidate` implicitly commits the change set; use `validate` to dry-run and `diff` to preview.

## NETCONF

Also supported (port 830). Standard `<get>` / `<get-config>` / `<edit-config>` / `<commit>` against the candidate, using the `srl_nokia-*` namespaces. Prefer gNMI or JSON-RPC for new automation; NETCONF is there for compatibility.

## Management

The out-of-band management interface lives in the `mgmt` network-instance (`mgmt0`), separate from the `default` instance carrying production traffic.

## Shell

SR Linux runs on Linux: the `bash` command drops to a shell on the box (handy for `ip`, logs under `/var/log/srlinux/`). SR OS has no equivalent general shell.
