# SR OS config format (MD-CLI: flat vs hierarchical)

MD-CLI can render the same configuration in several shapes. The command is `info`, optionally with an output modifier. Output is always relative to the current context.

## Hierarchical (default)

From `configure read-only` (context `/configure`):

```
    router "Base" {
        interface "system" {
            ipv4 {
                primary {
                    address 10.0.0.1
                    prefix-length 32
                }
            }
        }
    }
```

`info` (no modifier) shows this indented, nested form, one leaf per line. Best for humans reading structure. From the `/configure` context there is no `configure {` wrapper; a saved config (`admin save`) and `admin show configuration` wrap everything in `configure { ... }`.

## Flat

`info flat` renders one line per leaf, with the path relative to the current context. From `/configure`:

```
    router "Base" interface "system" ipv4 primary address 10.0.0.1
    router "Base" interface "system" ipv4 primary prefix-length 32
```

From `configure ... router "Base" interface "system"`, the same leaves print as `ipv4 primary address 10.0.0.1`. Best for `grep` and line-by-line diffs. Flat lines are valid input when you enter them in the same context they were printed from.

## Full context

`info full-context` renders each line with its absolute path, from any context:

```
    /configure router "Base" interface "system" ipv4 primary address 10.0.0.1
    /configure router "Base" interface "system" ipv4 primary prefix-length 32
```

These lines are valid input from any context, so this is the form to re-apply config as commands.

## Structured

- `info json` - JSON, keyed by YANG node names with the module prefix (`"nokia-conf:ipv4"`); ideal for programmatic parsing.
- `info xml` - XML in the `urn:nokia.com:sros:ns:yang:sr:conf` namespace, matching the YANG/NETCONF structure.

## Scoping and defaults

Run `info` from a context to limit output to that subtree, e.g. from `configure router "Base"`, `info flat` shows only that router. Add `detail` to include default values that are otherwise omitted (`info detail`, `info flat detail`); unset leaves then show as `## <leaf>` lines.

## When to use which

| Goal | Use |
|------|-----|
| Read/understand structure | `info` (hierarchical) |
| grep / diff / line-by-line | `info flat` |
| Re-apply config as commands from any context | `info full-context` |
| Feed a parser/program | `info json` |
| Build a NETCONF payload | `info xml` |
