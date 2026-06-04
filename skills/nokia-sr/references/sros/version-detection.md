# Detecting the SR OS version

The software release drives which YANG models apply, so determine it first.

## From a live device (CLI)

```
show version
```

Output begins with the TiMOS banner, e.g.:

```
TiMOS-B-25.10.R4 both/x86_64 Nokia 7750 SR Copyright (c) ...
```

The release is the `25.10.R4` token (`B` = both CPM/IOM image). `show system information` also reports it as the `System Version` field.

## From a live device (NETCONF / YANG)

Read the state path (verified in `nokia-state-system.yang`):

- `/nokia-state:state/system/version/version-number`
- `/nokia-state:state/system/version/version-string`

NETCONF `<get>` subtree filter:

```xml
<filter type="subtree">
  <state xmlns="urn:nokia.com:sros:ns:yang:sr:state">
    <system><version/></system>
  </state>
</filter>
```

With pySROS:

```python
v = connection.running.get("/nokia-state:state/system/version/version-number")
```

## From a config file

A saved SR OS config carries the TiMOS release in its header comment line (the `TiMOS-B-<version>` token, same format as `show version`).

> Verify the exact header wording against a real saved config from your environment: it differs between a classic `.cfg` save and an MD-CLI `admin save` / `info`-style export. Treat the `TiMOS-B-<version>` token as the reliable anchor; grep for `^# TiMOS` or `TiMOS-` in the file.

## Why it matters

Map the release to the YANG models before writing filters or templates:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/nokia-sr/scripts/ensure-yang.sh" sros 25.10.R4
```

To tell SR OS apart from SR Linux in the first place, see `../global/detecting-nos.md`.
