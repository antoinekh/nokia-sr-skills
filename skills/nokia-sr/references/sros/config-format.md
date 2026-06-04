# SR OS config format (MD-CLI: flat vs hierarchical)

MD-CLI can render the same configuration in several shapes. The command is `info`, optionally with an output modifier.

## Hierarchical (default)

```
configure
    router "Base" {
        interface "system" {
            ipv4 {
                primary {
                    address 10.0.0.1 prefix-length 32
                }
            }
        }
    }
```

`info` (no modifier) shows this indented, nested form. Best for humans reading structure.

## Flat

`info flat` renders one full-path command per line:

```
configure router "Base" interface "system" ipv4 primary address 10.0.0.1 prefix-length 32
```

Each line is the complete path to a leaf. Best for `grep`, diffing two configs line-by-line, and automation. Flat output is itself valid input: it can be pasted/loaded back to recreate the configuration ("unflattening" happens automatically as the device re-nests each path).

## Structured

- `info json` - JSON, keyed by YANG node names; ideal for programmatic parsing.
- `info xml` - XML matching the YANG/NETCONF structure.

## Scoping and context

Run `info` from a context to limit output to that subtree, e.g. from `configure router "Base"`, `info flat` shows only that router. Add `detail` to include default values that are otherwise omitted (`info detail`, `info flat detail`).

## When to use which

| Goal | Use |
|------|-----|
| Read/understand structure | `info` (hierarchical) |
| grep / diff / line-by-line | `info flat` |
| Feed a parser/program | `info json` |
| Build a NETCONF payload | `info xml` |
| Re-apply config as commands | `info flat` output |
