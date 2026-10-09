# Changelog

## Unreleased

### Added

- README: how to use the skill in OpenCode and other Agent Skills harnesses.

### Fixed

- `ensure-yang.sh`: an SR OS revision without a tag (for example `22.10.R10`) now fails with a clear error. It no longer falls back to the `sros_<maj>.<min>` branch, which holds the newest revision and was cached under the requested one.
- Skill commands call `ensure-yang.sh` by a path relative to the skill directory (Agent Skills convention), not through `${CLAUDE_PLUGIN_ROOT}`: Claude Code substitutes that variable only in `SKILL.md`, so the commands in the reference files failed, and other harnesses such as OpenCode never substitute it.

## v0.3.0 - 2026-06-09

### Added

- CI workflow (GitHub Actions): ShellCheck and the offline test suite run on every push and pull request.
- `ensure-yang.sh`: `-h`/`--help` handler backed by a single `usage()` function, also printed on the missing-argument error path.
- `ensure-yang.sh`: `GITHUB_TOKEN` / `GH_TOKEN` are sent as an Authorization header when set, lifting the unauthenticated api.github.com rate limit (60 requests/hour per IP); transient download failures are retried (`curl --retry 3`).
- This changelog, and a release checklist in the README (the plugin version lives in both `plugin.json` and `marketplace.json`).

### Fixed

- Test suite: failures inside subshell tests were not counted, so the suite could print `FAIL` lines yet still exit 0 ("all tests passed"). Failures are now tracked in a file so they propagate from subshells.

## v0.2.1 - 2026-06-04

### Fixed

- Quote the SKILL.md `description` to fix invalid YAML frontmatter.

## v0.2.0 - 2026-06-04

- Initial release: `nokia-sr` skill - NOS detection (SR OS vs SR Linux), on-demand YANG models via `ensure-yang.sh`, per-NOS version detection, config formats, NETCONF / MD-CLI / gNMI operations, and srpls language server pointers.
