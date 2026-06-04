# Detecting the NOS: SR OS vs SR Linux

Nokia ships two unrelated network operating systems. Identify which one you are dealing with before fetching models, parsing config, or driving the device - they share almost no CLI commands, model names, or config syntax.

| | SR OS (SROS) | SR Linux (SRL) |
|---|---|---|
| Platforms | 7750 SR, 7250 IXR, 7950 XRS | 7220 IXR, 7250 IXR, 7730 SXR |
| Base | TiMOS (proprietary) | Linux |
| YANG root modules | `nokia-conf`, `nokia-state` | `srl_nokia-*` |
| Config namespace | `urn:nokia.com:sros:ns:yang:sr:conf` | `urn:nokia.com:srlinux:*` |
| YANG repo | `nokia/7x50_YangModels` | `nokia/srlinux-yang-models` |
| Default CLI | MD-CLI or classic CLI | `sr_cli` |
| Native APIs | NETCONF, gRPC/gNMI, classic CLI | gNMI, JSON-RPC, NETCONF, CLI |

> Some 7250 IXR variants ship with either NOS, so don't decide on platform family alone - confirm with one of the stronger signals below (banner, model names, file suffix, version shape).

## How the language server distinguishes them

The Nokia `srpls` language server / `vscode-sr` extension key off these signals (see `references/global/language-server.md`). They are the most reliable cues.

### 1. File-name suffix (vscode-sr convention)

- `*.sros.cfg` -> SR OS
- `*.srl.cfg` -> SR Linux

### 2. First-line directive

Both NOSes let you pin the model in a header comment that tools read from the first lines:

```
# version=25.10.R4         # SR OS  (R-style release)
# version=25.10.3          # SR Linux (three-part numeric)
# platform=7750            # SR OS
# platform=7220-ixr-d3l    # SR Linux (platform names differ entirely)
```

The version *shape* alone is a strong hint: SR OS uses `MAJOR.MINOR.Rn` (e.g. `25.10.R4`); SR Linux uses `MAJOR.MINOR.PATCH` (e.g. `25.10.3`).

### 3. Banner / version token in the config

- SR OS configs carry a TiMOS token: `TiMOS-[A-Z]-<maj>.<min>.<rev>`, e.g. `TiMOS-B-25.10.R4`. (Regex used by srpls: `TiMOS-[A-Z]-(\d+\.\d+\.\S+)`.)
- SR Linux has no TiMOS banner; it relies on the `# version=` directive.

### 4. Comment prefixes

- SR OS comments start with `#`.
- SR Linux comments start with `#`, `//`, or `!`.

### 5. Top-level config keywords (braced format)

- SR OS: `configure { ... }` with quoted list keys, e.g. `router "Base" { interface "system" { ... } }`. Flat lines begin with `configure router "Base" ...`.
- SR Linux: top-level apps like `network-instance default { ... }`, `interface ethernet-1/1 { subinterface 0 { ... } }`, `system { ... }`. List keys are unquoted; flat lines begin with `set / ...`.

## On a live device

| Signal | SR OS | SR Linux |
|--------|-------|----------|
| `show version` banner | `TiMOS-B-25.10.R4 ... Nokia 7750 SR` | `Hostname / Software Version: vX.Y.Z` |
| Prompt | `*A:node#` (classic) or `[/]\nA:admin@node#` (MD-CLI) | `--{ running }--[  ]--\nA:node#` |
| NETCONF hello modules | `nokia-conf`, `nokia-state` | `srl_nokia-*` |
| gNMI capabilities models | `nokia-conf` namespaces | `srl_nokia-*` namespaces |
| Shell | no general shell | drops to `bash` (`bash` command) |

## Quick decision

```
Has TiMOS-... banner OR nokia-conf paths OR *.sros.cfg OR version MAJOR.MINOR.Rn  -> SR OS
Has srl_nokia-* paths OR *.srl.cfg OR network-instance/ethernet-1/N OR version MAJOR.MINOR.PATCH -> SR Linux
```

## When unsure, ask

If none of the signals above are present, or they conflict (e.g. a stray file name vs the config body), **do not guess the NOS** - ask the user to confirm whether it is SR OS or SR Linux. The wrong choice sends every later step (models, CLI, syntax) down the wrong path, so a one-line confirmation is cheaper than redoing the work.

Once identified, continue with that NOS's version-detection reference, then fetch its YANG models (`references/global/yang-models.md`).
