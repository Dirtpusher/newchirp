# NewChirp Agent Guide

This repository keeps generated OKF knowledge bundles so coding agents can
answer structural questions without re-reading large source files.

## Automatic freshness

VS Code is configured to run `Watch OKF knowledge graph` when the workspace
opens. That task performs an initial refresh and then watches `lib/` and
`scripts/` for saves, updating only the concepts affected by the changed files.
There is also a manual `Refresh OKF knowledge graph` task.

## Knowledge bundles

- `okf_bundle` — Dart application code under `lib/`
- `okf_bundle_scripts` — Python support scripts under `scripts/`

## Use the bundle first

For a focused question, run an OKF lookup before opening a whole source file:

```sh
/tmp/newchirp-okf-venv/bin/okf lookup --bundle ./okf_bundle --compact NewChirpHome
/tmp/newchirp-okf-venv/bin/okf lookup --bundle ./okf_bundle --compact RadioChannel
/tmp/newchirp-okf-venv/bin/okf lookup --bundle ./okf_bundle_scripts --compact chirp_bridge
```

For broader context, start with:

```sh
sed -n '1,220p' okf_bundle/SUMMARY.md
sed -n '1,220p' okf_bundle_scripts/SUMMARY.md
```

If the OKF binary is not installed, read the summary and index files directly
and use `find okf_bundle -name '<ConceptName>.md'`.

## Keep the bundles up to date

After editing anything under `lib/` or `scripts/`, refresh the relevant bundle:

```sh
./scripts/update_okf.sh
```

Useful modes:

```sh
./scripts/update_okf.sh --bootstrap   # create the isolated venv and install okf-generator
./scripts/update_okf.sh --watch       # run incremental watchers for lib and scripts
```

Do not index `build/`, `build_support/`, or cached CHIRP/Python trees. The
bundles intentionally cover only source directories.
