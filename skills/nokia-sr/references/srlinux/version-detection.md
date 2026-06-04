# Detecting the SR Linux version

The software release drives which YANG models apply, so determine it first. SR Linux releases are three-part numeric: `MAJOR.MINOR.PATCH` (e.g. `25.10.3`), usually written with a leading `v` on tags/banners (`v25.10.3`).

To tell SR Linux apart from SR OS in the first place, see `../global/detecting-nos.md`.

## From a live device (CLI)

```
show version
```

Reports a `Software Version` field, e.g. `v25.10.3`. Equivalently, read it from the state datastore (space-separated path tokens):

```
info from state system information version
```

## From a live device (gNMI / JSON-RPC / NETCONF)

The version is the leaf `/system/information/version`. This is verified against the model: `srl_nokia-system-info.yang` augments `/system` with `container information { leaf version { type string; config false; } }`, so it is **state-only** (read it from the state datastore, not config).

```bash
# gNMI
gnmic -a <node>:57400 get --path /system/information/version --encoding json_ietf
```

To re-confirm against the exact release you are targeting:

```bash
YANG=$("${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" srlinux 25.10.3)
grep -n "leaf version" "$YANG/srlinux-yang-models/srl_nokia/models/system/srl_nokia-system-info.yang"
```

## From a config file

SR Linux saved configs do **not** carry a TiMOS-style banner. The release is conveyed by the `# version=` header directive that the language server reads:

```
# version=25.10.3
```

If there is no directive, the version must be known out of band (from the device or the lab/topology that produced the config).

## Why it matters

Map the release to the YANG models before writing paths or templates:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" srlinux 25.10.3
```
