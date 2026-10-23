---
okf_version: "0.2"
type: Function
title: _windowsSerialPorts
description: "Windows: read the live COM ports from the SERIALCOMM registry key, then"
resource: services/radio_bridge.dart
tags:
  - "lang:dart"
  - "type:Function"
  - "module:services"
  - "domain:radio_bridge.dart"
  - "git:branch:main"
  - "git:repo:newchirp"
timestamp: "2026-10-23T17:57:26Z"
concept_id: services/radio_bridge/windowsSerialPorts
language: dart
---

# _windowsSerialPorts

Windows: read the live COM ports from the SERIALCOMM registry key, then

## Signature

```dart
Future_windowsSerialPorts_windowsSerialPorts
```

## Docstring

Windows: read the live COM ports from the SERIALCOMM registry key, then
fall back to .NET's SerialPort.GetPortNames() so only real ports show up.

## Source
Lines 238–238 in `services/radio_bridge.dart`

## Relationships

| Type | Target |
|------|--------|
| related | [radio_bridge](/services/radio_bridge.md) |
