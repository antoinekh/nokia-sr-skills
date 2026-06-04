# SR Linux config format

SR Linux config is fully YANG-modelled and edited through `sr_cli`. The same configuration can be rendered in several shapes via `info`.

## Braced (default)

```
network-instance default {
    interface ethernet-1/1.0 {
    }
    protocols {
        bgp {
            autonomous-system 65000
            router-id 10.0.0.1
        }
    }
}
```

`info` (no modifier) shows the indented, nested form. List keys are **unquoted** (`interface ethernet-1/1.0`), unlike SR OS which quotes them. Best for humans.

## Flat (`set` commands)

`info flat` renders one full-path `set` command per line:

```
set / network-instance default protocols bgp autonomous-system 65000
set / network-instance default protocols bgp router-id 10.0.0.1
```

Each line begins with `set /` followed by the complete path to a leaf. Best for `grep`, diffing, and automation. Flat output is itself valid input: paste/load it back to recreate the config. (This `set /` prefix is the SR Linux flat marker - contrast SR OS, whose flat lines begin with `configure ...`.)

## Structured

- `info | as json` (or `info from state ... | as json`) - native JSON, the same shape gNMI / JSON-RPC use. SR Linux is JSON-first, so this is the canonical machine form.

## Datastores and context

`info` reads the current candidate; add a source to read another datastore:

| Command | Reads |
|---------|-------|
| `info` | current edit context (candidate) |
| `info from running` | running config |
| `info from state` | operational state (config + state) |
| `info detail` | include default values |

Run `info` from a context to scope output, e.g. from `network-instance default`, `info` shows only that instance.

## Header directives (language server)

Tools key off first-line comments (comment prefixes are `#`, `//`, `!`):

```
# version=25.10.3
# platform=7220-ixr-d3l
```

The `# platform=` directive matters: interface names are platform-specific (`ethernet-1/1`, `ethernet-1/49`, ...). The srpls language server uses it to offer valid interface completions and flag unknown ones. Common platforms include the 7220 IXR D-series (`7220-ixr-d2l`, `7220-ixr-d3l`, ...) and H-series; list the full set from the language server's known platforms.

## Top-level apps (vs SR OS)

SR Linux config is organized by application at the top level - `system`, `interface`, `network-instance`, `routing-policy`, `acl`, `tunnel`, ... There is no `configure { router "Base" }` container; that braced/quoted shape is SR OS. See `../global/detecting-nos.md`.
