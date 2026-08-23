---
description: 'Top-level OKF summary: 157 concepts across 4 domains and 10 modules'
okf_version: '0.2'
timestamp: '2026-08-23T10:03:33Z'
title: okf_bundle — Knowledge Summary
type: Index
---

# okf_bundle — Knowledge Summary

> OKF v0.2 bundle | 157 concepts | 4 domains | 10 modules

## Stats

| Type | Count |
|------|-------|
| Function | 115 |
| Class | 30 |
| Module | 12 |

| Language | Concepts |
|----------|----------|
| dart | 157 |

## Domain Map

Use these links to navigate the bundle or prime an AI agent with focused context.

### [._main.dart](._main.dart/index.md) — 1 concepts

- [](/index.md) (1 concepts)

### [main.dart](main.dart/index.md) — 97 concepts

- [main](main/index.md) (97 concepts)

### [models](models/index.md) — 9 concepts

- [models/radio_channel](models/radio_channel/index.md) (8 concepts)
- [models/](models/index.md) (1 concepts)

### [services](services/index.md) — 50 concepts

- [services/radio_bridge](services/radio_bridge/index.md) (19 concepts)
- [services/chirp_csv](services/chirp_csv/index.md) (10 concepts)
- [services/column_layout_store](services/column_layout_store/index.md) (6 concepts)
- [services/radio_image_store](services/radio_image_store/index.md) (6 concepts)
- [services/radio_selection_store](services/radio_selection_store/index.md) (6 concepts)
- [services/](services/index.md) (3 concepts)

## Key Concepts

Highest-value concepts across all domains (Classes and Functions with rich descriptions).

| Concept | Type | Module | Description |
|---------|------|--------|-------------|
| [_resolvePython](/services/radio_bridge/resolvePython.md) | Function | `services/radio_bridge.dart` | The bundled CHIRP tree uses Python 3.10+ syntax, so prefer a… |

## Usage with OpenCode

```bash
# Prime full context
RUN cat ./okf_bundle/SUMMARY.md

# Prime specific domain
RUN cat ./okf_bundle/._main.dart/index.md

# Find a concept
RUN find ./okf_bundle -name '<ConceptName>.md' | xargs cat
```
