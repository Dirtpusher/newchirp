# NewChirp

NewChirp is a Flutter desktop channel editor for amateur and GMRS radios. It
uses the CHIRP driver tree as a compatibility layer for safe radio transfers
while presenting a fresh desktop interface.

See [docs/SOFTWARE_ROADMAP.md](docs/SOFTWARE_ROADMAP.md) for the complete
implementation history, architecture, known risks, and prioritized next work.

## Included

- CHIRP-compatible CSV import and export
- CSV/GMRS template insertion starting at any channel number
- Searchable channel library with validation and detailed editing
- Right-click copy, cut, paste, and duplicate for channel rows
- Right-click clear channel, which clears it from the radio on the next write
- Undo/redo with keyboard shortcuts
- 22-channel GMRS starter library
- USB serial-port discovery
- CHIRP radio-model catalog and guarded read/write workflow
- Reusable per-model radio images after the first read
- Real transfer progress from CHIRP read/write status with percentage and elapsed time
- Radio-wide settings editor for drivers that expose CHIRP global settings
- Help-context icons with detailed instructions
- Restore stock channels from the bundled CHIRP GMRS config
- macOS, Windows, and Linux Flutter projects
- In-app "Check for updates" against the newchirp.net download manifest

## Updates

The About screen checks newchirp.net for a newer release. The app reads a JSON
manifest (default `https://newchirp.net/api/releases/latest`) shaped like:

```json
{
  "version": "1.0.2",
  "release_url": "https://newchirp.net/#download",
  "downloads": { "windows": "...", "macos": "...", "linux": "..." }
}
```

Only `version` is required; `release_url` (or `url`) is optional and is opened
when the user accepts the update. The installed version is `_newChirpVersion`
in `lib/main.dart` and should be kept in sync with `version` in `pubspec.yaml`.
The check logic lives in `lib/services/update_checker.dart`.

When cutting a release, bump the version in all three places so they agree:

- `_newChirpVersion` in `lib/main.dart`
- `version` in `pubspec.yaml`
- `RELEASE.version` in the web server (`/opt/newchirp/server.mjs`), which
  serves `GET /api/releases/latest`

## Run

```sh
flutter pub get
flutter run -d macos
```

The macOS app build now bundles a private Python runtime and the CHIRP driver
tree inside `NewChirp.app`, so end users do not need to install Python or CHIRP.
For development, a custom CHIRP location may still be selected by setting
`CHIRP_SOURCE` to the folder containing the `chirp` Python package. Builds also
check for the latest CHIRP-next release and fetch the newest master source into
`build_support` automatically; set `NEWCHIRP_AUTO_UPDATE_CHIRP=0` to keep the
current snapshot instead. NewChirp bundles the headless serial dependency used
by the CHIRP drivers; do not install CHIRP's wxPython GUI requirements.

Always read a radio before writing it. NewChirp intentionally keeps writing
locked until a matching radio image has been downloaded in the current session.

## Verify and build

```sh
flutter analyze
flutter test
flutter build macos
```

### Windows

Build status and resumption checklist: `docs/BUILD_PROGRESS.md`.

On a Windows machine with the Flutter SDK and Visual Studio (C++ workload)
installed, build the release bundle and Inno Setup installer with:

```powershell
.\scripts\build_windows_installer.ps1
```

The script runs `flutter pub get`, `flutter build windows --release`, bundles a
private Python runtime and the CHIRP driver tree next to `newchirp.exe`, and
then compiles `build\NewChirp-Installer-<version>.exe`. Pass
`-Configuration debug` to build a JIT debug app instead, or `-BundleDir` to
package an already-built bundle. The runtime and CHIRP sources are downloaded
the first time and cached under `build_support\`.

Release AOT builds need `gen_snapshot.exe`, which Windows Smart App Control
blocks when it is enabled. If `flutter build windows --release` fails with an
Application Control message, turn Smart App Control off (Windows Security →
App & browser control → Smart App Control), restart, and re-run the script.
Use `-Configuration debug` only for a local dev build; debug Flutter binaries
link the Visual Studio debug CRT and are not intended for clean end-user
machines.

## Code knowledge graph

This project keeps OKF knowledge bundles for coding agents:

- `okf_bundle` indexes the Dart application source under `lib/`.
- `okf_bundle_scripts` indexes the Python support scripts under `scripts/`.

Read `AGENTS.md` for lookup instructions. Refresh the bundles after source
changes with:

```sh
./scripts/update_okf.sh
```

VS Code is configured to refresh the bundles when the workspace opens and to
watch `lib/` and `scripts/` for saves automatically.
