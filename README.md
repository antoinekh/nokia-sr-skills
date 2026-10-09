# nokia-sr-skills

A Claude Code skill plugin that teaches Claude how to inspect and operate Nokia's two SR network operating systems - **SR OS** (SROS) and **SR Linux** (SRL): telling the two apart, fetching the right YANG models on demand, reading the software version, understanding each NOS's config formats, and applying NETCONF / MD-CLI / gNMI behaviors. It also points to Nokia's `srpls` language server.

## Install

```
/plugin marketplace add antoinekh/nokia-sr-skills
/plugin install nokia-sr-skills@antoinekh
```

### Other harnesses

OpenCode and other [Agent Skills](https://agentskills.io) harnesses do not install Claude Code plugins. Link the skill folder into one of their skill directories instead, for example for OpenCode:

```
mkdir -p ~/.config/opencode/skills
ln -s "$PWD/skills/nokia-sr" ~/.config/opencode/skills/nokia-sr
```

## What it does

- **NOS detection** - tell SR OS from SR Linux (file, config, live device); ask the user when unsure.
- **On-demand YANG models** - `ensure-yang.sh <nos> <version>` checks a dedicated local cache (`~/.cache/nokia-sr/yang/<nos>/<version>`) and downloads the matching release tarball - the same source and repos the [srpls](https://github.com/srl-labs/srpls) language server uses - only if missing. SR OS from [nokia/7x50_YangModels](https://github.com/nokia/7x50_YangModels), SR Linux from [nokia/srlinux-yang-models](https://github.com/nokia/srlinux-yang-models).
- **Version detection** - per NOS, from a live device or a config file.
- **Config formats** - SR OS `info` / `info flat` / `info json`; SR Linux braced vs `set` flat, JSON, platform-aware interfaces.
- **Operations** - SR OS NETCONF / MD-CLI quirks; SR Linux gNMI / JSON-RPC / NETCONF / CLI.
- **Language server** - pointers to `srpls` and the `vscode-sr` extension.

## Configuration

| Environment variable | Default | Purpose |
|----------------------|---------|---------|
| `NOKIA_SR_YANG_DIR` | `${XDG_CACHE_HOME:-~/.cache}/nokia-sr/yang` | Override the directory where YANG releases are cached and looked up. |
| `GITHUB_TOKEN` / `GH_TOKEN` | unset | Sent as an Authorization header on GitHub API requests; lifts the unauthenticated rate limit (60 requests/hour per IP). |

## Layout

```
skills/nokia-sr/
  SKILL.md
  scripts/ensure-yang.sh
  references/
    global/{detecting-nos,yang-models,yang-tooling,language-server}.md
    sros/{version-detection,config-format,operate}.md
    srlinux/{version-detection,config-format,operate}.md
```

## Tests

```
bash tests/test_ensure_yang.sh
```

CI runs ShellCheck, this suite, the Agent Skills validator (`skills-ref validate`) and `claude plugin validate --strict` on every push and pull request.

## Releasing

1. Bump `version` in `.claude-plugin/plugin.json` (the only place it is set: the marketplace entry takes it from there).
2. Move the `## Unreleased` entries of `CHANGELOG.md` into a new `## vX.Y.Z - <date>` block.
3. Commit and tag `vX.Y.Z`.

## Attribution

YANG models are downloaded from Nokia's public [7x50_YangModels](https://github.com/nokia/7x50_YangModels) and [srlinux-yang-models](https://github.com/nokia/srlinux-yang-models) repositories and are subject to Nokia's license. This plugin does not redistribute them.

## License

MIT
