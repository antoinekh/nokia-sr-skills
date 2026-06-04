# YANG models (SR OS & SR Linux)

Both Nokia NOSes are YANG-modelled: the models define every configuration and state path. Always verify paths against the models for the *target software release* rather than guessing - paths are case-sensitive and version-dependent.

## Getting the models

Use the bundled `ensure-yang.sh`. First arg is the NOS, second is the version. It checks a local cache and downloads the matching release only if missing:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" sros 25.10.R4
"${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" srlinux 25.10.3
```

It prints the local YANG release directory on stdout. Cache location:

1. `$NOKIA_SR_YANG_DIR` if set (explicit override)
2. otherwise `${XDG_CACHE_HOME:-~/.cache}/nokia-sr/yang/<nos>/<version>`

## How it downloads (same source as the language server)

The script fetches a GitHub release **tarball** - the exact mechanism the `srpls` / `vscode-sr` tooling uses - and extracts it with `--strip-components=1`:

```
https://api.github.com/repos/<repo>/tarball/<ref>
```

| NOS | Repo | Ref it fetches |
|-----|------|----------------|
| SR OS | `nokia/7x50_YangModels` | tag `sros_<maj>.<min>.r<rev>` (e.g. `sros_25.10.r4`), falling back to branch `sros_<maj>.<min>` |
| SR Linux | `nokia/srlinux-yang-models` | tag `v<maj>.<min>.<patch>` (e.g. `v25.10.3`) |

Notes:
- SR OS tags are lowercase (`sros_25.10.r4`); the cache dir keeps the canonical `25.10.R4`.
- SR Linux's `main` branch holds only docs - the YANG files live **only on the version tags**, so a valid three-part version (and thus tag) is required.

Manual equivalent:

```bash
# SR OS
curl -fsSL https://api.github.com/repos/nokia/7x50_YangModels/tarball/sros_25.10.r4 \
  | tar -xz --strip-components=1 -C ./sros-25.10.R4
# SR Linux
curl -fsSL https://api.github.com/repos/nokia/srlinux-yang-models/tarball/v25.10.3 \
  | tar -xz --strip-components=1 -C ./srlinux-25.10.3
```

(`git clone -b <tag> --depth 1 <repo>` also works and produces identical files.)

## Layout

### SR OS (`nokia/7x50_YangModels`)

Everything lives under the release's `YANG/` directory:

- top-level `*.yang` - individual modules: type definitions (`nokia-types-*`), operational (`nokia-oper-*`), notifications, per-feature config. The master config/state trees are *not* here - they are the combined modules below.
- `nokia-combined/` - two modules, `nokia-conf.yang` (config) and `nokia-state.yang` (state), each with all of its own submodules inlined. They still *import* the sibling `nokia-types-*` and `nokia-sros-yang-extensions` modules (plus IETF/OpenConfig), so a YANG parser needs the whole `YANG/` dir on its search path - but for a plain `grep` these single files are the best target.
- `nokia-submodule/` - the same content split into hundreds of submodule files.
- `ietf/`, `openconfig/` - standard IETF and OpenConfig modules. `revisions.txt` - per-module revision dates.

### SR Linux (`nokia/srlinux-yang-models`)

Models live under `srlinux-yang-models/`:

- `srl_nokia/models/` - the native SR Linux modules, grouped by feature area (e.g. `system/`, `interfaces/`, `network-instance/`). These are the config and state trees.
- `ietf/`, `iana/`, `openconfig/` - standard / OpenConfig modules.
- `mappings/` - OpenConfig-to-native mappings.

## Search recipes

`ensure-yang.sh` prints the release root; grep recursively so it works for either layout.

```bash
YANG=$("${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" sros 25.10.R4)

# Find where a node is defined
grep -rn "leaf interface-name" "$YANG"

# SR OS: namespace of the master config tree (the combined module)
grep -n "^\s*namespace" "$YANG/YANG/nokia-combined/nokia-conf.yang"

# Available RPCs / actions
grep -rn "rpc \|action " "$YANG"
```

```bash
YANG=$("${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" srlinux 25.10.3)

# SR Linux: list the native model areas
ls "$YANG/srlinux-yang-models/srl_nokia/models"

# Find a node
grep -rn "leaf admin-state" "$YANG/srlinux-yang-models/srl_nokia"
```

Online model browsers (no download needed):

- SR Linux: <https://yang.srlinux.dev>
- SR OS: Nokia's "SR OS YANG navigation" portal (<https://network.developer.nokia.com/sr/learn/yang/sr-os-yang-navigation-101/>) and the community path finder <https://yang.labctl.net>.

To turn the downloaded models into a readable path tree, or to validate config/state data you pulled from a device, see `references/global/yang-tooling.md`.
