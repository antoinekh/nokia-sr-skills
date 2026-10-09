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

A config saved from MD-CLI (`admin save`, or the output of `admin show configuration`) starts with a comment header, then the braced `configure { ... }` block. Example from an SR-SIM 26.3.R1:

```
# TiMOS-B-26.3.R1 both/x86_64 Nokia 7750 SR-1 Copyright (c) 2000-2026 Nokia.
# All rights reserved. All use subject to applicable license agreements.
# Built on Wed Mar 11 20:17:13 UTC 2026 by builder in /builds/263B/R1/panos
# Configuration format version 26.3 revision 0
```

The release is the `TiMOS-B-<version>` token (`grep -m1 'TiMOS-' <file>`). Output of `info` has no header, so the version must then come from the device or the user. The header of a classic CLI save is not checked here; anchor on the `TiMOS-` token there too.

## Why it matters

Map the release to the YANG models before writing filters or templates:

```bash
"<skill-dir>/scripts/ensure-yang.sh" sros 25.10.R4
```

To tell SR OS apart from SR Linux in the first place, see `../global/detecting-nos.md`.
