---
name: nokia-sr
description: "Use when you need to inspect or operate a Nokia SR network OS - SR OS (SROS, 7750/7250/7950) or SR Linux (SRL) - and must look up how: telling the two NOSes apart, fetching the matching YANG models, finding the software release, understanding config formats (info / info flat, braced vs flat), or applying NETCONF / MD-CLI / gNMI behaviors. Also covers the srpls language server."
---

# Nokia SR (SR OS & SR Linux) router skill

Helps you inspect and operate Nokia's two network operating systems:

- **SR OS** (SROS) - the classic 7750 SR / 7250 IXR / 7950 XRS TiMOS-based OS.
- **SR Linux** (SRL) - the newer Linux-based, fully YANG-modelled OS.

They share concepts (YANG-driven config, NETCONF/gNMI) but differ in CLI, config syntax, models, and tooling. Work in this order, loading the one reference you need.

## Step 1: Which NOS is it?

If you don't already know, identify SR OS vs SR Linux first - it decides every later step (models, CLI, syntax). See `references/global/detecting-nos.md`.

**If detection is inconclusive or you are not sure, stop and ask the user to confirm which NOS it is** rather than guessing - picking the wrong NOS sends you to the wrong models, CLI, and syntax.

## Step 2: Get the release, then the YANG models

**Rule for any config / "how do I X" question (e.g. "how do I configure X on SR OS?"): do not answer from memory.** First ask the user for the software version (or confirm it from the device/config), then verify the exact paths, keywords, and syntax against the YANG models for *that* version before giving an answer. Paths are case-sensitive and version-dependent, so an answer that is not checked against the pinned models is a guess.

YANG paths are case-sensitive and version-dependent, so pin the release first.

- SR OS version - `references/sros/version-detection.md`
- SR Linux version - `references/srlinux/version-detection.md`

Then fetch the matching models on demand (the script is NOS-aware - first arg is the NOS, second is the version):

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" sros 25.10.R4
"${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" srlinux 25.10.3
"${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" sros latest   # newest release
```

SR OS needs an explicit revision (`25.10.R4`, not bare `25.10`); SR Linux needs the three-part version (`25.10.3`); `latest` resolves the newest release from GitHub. It prints the local YANG release directory (downloading from Nokia's GitHub only if not already cached). How it works and how to search the models: `references/global/yang-models.md`.

## Where to look

### Global (both NOSes)

| You need to... | Read |
|----------------|------|
| Tell SR OS and SR Linux apart (file, config, live device) | `references/global/detecting-nos.md` |
| Obtain / search YANG models for a release | `references/global/yang-models.md` |
| Render a YANG path tree or validate device data offline (pyang / yanglint) | `references/global/yang-tooling.md` |
| Set up the srpls language server / VS Code extension | `references/global/language-server.md` |

### SR OS (SROS)

| You need to... | Read |
|----------------|------|
| Get the SR OS release from a device or config file | `references/sros/version-detection.md` |
| Understand `info` vs `info flat` vs `info json` output | `references/sros/config-format.md` |
| Push/diff config over NETCONF or navigate MD-CLI | `references/sros/operate.md` |

### SR Linux (SRL)

| You need to... | Read |
|----------------|------|
| Get the SR Linux release from a device or config file | `references/srlinux/version-detection.md` |
| Understand SR Linux config (braced vs `set` flat, platform) | `references/srlinux/config-format.md` |
| Operate over gNMI / JSON-RPC / CLI | `references/srlinux/operate.md` |

## Key reminders

- Identify the NOS before anything else; SR OS and SR Linux share almost no CLI or model names.
- For any config or "how do I X" question: ask for the version first, then verify against the YANG model for that version before answering - never answer from memory.
- Pin the YANG release to the device's actual version before writing filters or templates.
- Before proposing a `commit`, always propose running the compare/diff first to confirm the change: SR OS `compare` / `md-compare`, SR Linux `diff` / `commit validate`. See each NOS's operate reference.
- SR OS only: check configuration-mode (`classic` / `mixed` / `model-driven`) before NETCONF candidate edits, and set `nc:operation` explicitly. See `references/sros/operate.md`.
- Both NOSes have a flat config form that round-trips as valid input (`info flat`).
