# Offline YANG tooling: explore paths & validate data (pyang, yanglint)

`ensure-yang.sh` (see `yang-models.md`) gives you the model files for a pinned release. Two standard tools turn those models into something you can read and validate data against, without a live device:

- **pyang** - render a model as a readable path tree, so you see the exact (case-sensitive) path, node type, and structure of everything that is gettable/settable.
- **yanglint** (from CESNET **libyang**) - validate real instance data (an XML/JSON config or state dump you pulled from a device) against the models. This is the one thing `grep` and `pyang` cannot do: check that a *value* is legal for its leaf.

Both complement, not replace, the device's own checks (`commit validate` / `validate`, see each NOS's `operate.md`) and the in-editor srpls checks (see `language-server.md`). Use the offline tools when you have the models and a data file but no box to point at.

## Running the tools (no sudo)

Neither tool needs a system install or sudo:

| Tool | How to run |
| ---- | ---------- |
| pyang | Prefer `uv tool install pyang` (or `uvx pyang ...`) - pure Python, gives the newest pyang; avoid a bare `pip install` (modern distros reject it). No uv? Docker fallback: `docker run --rm -v "$YANG":/yang:ro ghcr.io/hellt/pyang:latest pyang ...` (name `pyang` explicitly). |
| yanglint | `docker run --rm -v "$YANG":/yang:ro -v "$PWD":/data ghcr.io/antoinekh/yanglint:latest ...` (a C tool, so Docker avoids building libyang). |

`ghcr.io/antoinekh/yanglint` is rebuilt by CI on each new libyang release, so `:latest` tracks a current libyang that parses Nokia's models; pin `:<libyang-version>` (e.g. `:3.13.6`) for reproducibility. Source / Dockerfile: <https://github.com/antoinekh/dockerfiles>.

In any Docker command the mounted model dir is `/yang` inside the container, so its paths are `/yang/...`; with native pyang they stay `$YANG/...`.

## Explore the path tree (pyang -f tree)

The tree is usually faster than `grep` for "what is the path to X" and "what children does it have". But the tree shows only the path, node **type**, and structure - **not** enum values, defaults, or descriptions. For those, `grep` the leaf: `grep -A14 'leaf configuration-mode'` reveals the `classic / model-driven / mixed` enum that the tree only labels `enumeration`. The two are complementary.

### SR OS

The combined module inlines its own submodules but still **imports** the sibling `nokia-types-*` / extension modules and IETF/OpenConfig, so put the top-level `YANG/` dir plus its `ietf/` and `openconfig/` subdirs on `-p` (pyang's `-p` does not recurse):

```bash
YANG=$("${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" sros 25.10.R4)
COMBINED="$YANG/YANG/nokia-combined/nokia-conf.yang"   # nokia-state.yang for the state tree
SEARCH=(-p "$YANG/YANG" -p "$YANG/YANG/ietf" -p "$YANG/YANG/openconfig")

# Whole tree (huge), or scope + cap depth:
pyang "${SEARCH[@]}" -f tree --tree-path /configure/system/management-interface --tree-depth 4 "$COMBINED"

# No uv? Same via Docker (paths become /yang/..., and name 'pyang' explicitly):
docker run --rm -v "$YANG":/yang:ro ghcr.io/hellt/pyang:latest pyang \
  -p /yang/YANG -p /yang/YANG/ietf -p /yang/YANG/openconfig -f tree \
  --tree-path /configure/system/management-interface --tree-depth 4 \
  /yang/YANG/nokia-combined/nokia-conf.yang
```

`pyang "${SEARCH[@]}" "$COMBINED"` with no `-f` just parses the model: silent + exit 0 means it is well-formed for that release (a quick schema sanity check).

### SR Linux

SR Linux splits its models across many feature folders that import each other. Easiest no-install way to browse structure is the online browser <https://yang.srlinux.dev>; on the downloaded models, `grep -rn` finds nodes and values directly (see `yang-models.md`). pyang needs every subdir on `-p` here (no recursion), so it is fiddly; yanglint's `-p` **recurses**, so one mounted path covers the whole tree:

```bash
SRL="$("${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" srlinux 25.10.3)/srlinux-yang-models"
docker run --rm -v "$SRL":/srl:ro ghcr.io/antoinekh/yanglint:latest \
  -p /srl -f tree /srl/srl_nokia/models/network-instance/srl_nokia-network-instance.yang
```

## Validate data against the model (yanglint)

Save the data first - e.g. a NETCONF `<get-config>` reply, `pysros` output, or `gnmic get ... --encoding json_ietf` - then validate it for the pinned release. Mount the model dir and your data dir:

```bash
YANG=$("${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" sros 25.10.R4)
yl() { docker run --rm -v "$YANG":/yang:ro -v "$PWD":/data ghcr.io/antoinekh/yanglint:latest "$@"; }

yl -p /yang/YANG -t edit /yang/YANG/nokia-combined/nokia-conf.yang /data/myconfig.xml
```

A clean file exits 0 (`libyang warn:` lines are advisory). A bad value is rejected with its exact path (and, on a current libyang, the input line) - e.g. an XML with `configuration-mode` set to `bogus-mode`:

```text
libyang err : Invalid enumeration value "bogus-mode". (/nokia-conf:configure/system/management-interface/configuration-mode) (line 4)
YANGLINT[E]: Failed to parse input data file "/data/myconfig.xml".
```

SR Linux JSON is identical - mount `$SRL` and point at the module(s) the data spans:

```bash
docker run --rm -v "$SRL":/srl:ro -v "$PWD":/data ghcr.io/antoinekh/yanglint:latest \
  -p /srl -t config /srl/srl_nokia/models/network-instance/srl_nokia-network-instance.yang /data/netinst.json
```

**Pick the right `-t`:** `edit` = a partial / edit-config snippet, `config` = a whole config datastore, `data` = a `<get>` / `info from state` dump (config + state). A partial snippet may be rejected under `-t config` with "missing mandatory node" depending on the model - if that happens, use `-t edit`. To validate a full datastore cleanly, load every module the data spans.

## When to use which

| Goal | Tool | Install |
| ---- | ---- | ------- |
| Browse structure / find a node's exact path & type | `pyang -f tree` | uv (Docker fallback) |
| See a leaf's allowed values / default / description | `grep -rn` in the model dir (the tree omits these) | none |
| Validate config/state *values* against the model, offline | `yanglint` via `ghcr.io/antoinekh/yanglint:latest` | Docker (no sudo) |
| Validate a change before applying it on the box | `commit validate` / `validate` (see `operate.md`); or srpls in-editor | none |
