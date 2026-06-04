# Language server: srpls & the VS Code extension

When you want editor support (completion, validation, hover, go-to-path) for Nokia SR OS or SR Linux config files, use Nokia SR Labs' language server.

## srpls - the language server

`srpls` ("SR please") is an LSP server for **both** SR Linux and SR OS (model-driven) config files. It works with any LSP-compatible editor.

- Repo: <https://github.com/srl-labs/srpls>
- It checks the config against the YANG model for a chosen software release and provides keyword completion, hover, document symbols, folding, and flatten/unflatten.
- You don't run `srpls` directly: it is installed and driven by the `vscode-sr` extension (see below), which selects the NOS and release for it.

It loads YANG models under `~/.srpls/` and detects the target version from the document header (`# version=...`) or, for SR OS, a `TiMOS-...` banner. This skill's `ensure-yang.sh` fetches the **same** models from the **same** repos (see `references/global/yang-models.md`); it keeps its own cache under `~/.cache/nokia-sr/` rather than `~/.srpls/`.

## vscode-sr - the VS Code extension

The editor-facing front end that bundles and drives `srpls`:

- Repo: <https://github.com/srl-labs/vscode-sr>
- Marketplace: "Nokia SR Linux & SR OS Language Server" (`srl-labs.sr-vscode`).
- Recognizes `*.sros.cfg` (SR OS) and `*.srl.cfg` (SR Linux) files.
- Downloads the `srpls` binary into `~/.srpls` (or `%USERPROFILE%\.srpls`) and the matching YANG models on demand.

### Quickstart

1. Create a file named `myconfig.srl.cfg` (or `.sros.cfg`).
2. Put the platform / version on the first line: `# platform=ixr-d3l` and/or `# version=25.10.3`.
3. Start typing - completions appear from the YANG model.

Use this reference whenever the user asks for a "language server", "LSP", "autocomplete", "linting", or editor tooling for Nokia SR config.
