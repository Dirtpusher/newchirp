# NewChirp Windows Build Progress

Last updated: 2026-08-23 by Codex (agent)

This file is the resumption checklist for the Windows build and installer work.
Read it after a reboot or when handing the task to another agent.

## Goal

Produce a release Windows build (`newchirp.exe`) and an Inno Setup installer that
end users can run on a clean Windows machine.

## What is already done

- Flutter SDK 3.47.1 was originally used on this machine. Windows release
  builds must now use Flutter 3.44.2: 3.47.x can crash on startup or show a
  black window on older Windows 10 GPUs limited to D3D11 feature level 9_3.
- Installed Inno Setup 6.7.3 at
  `C:\Users\rlopez\AppData\Local\Programs\Inno Setup 6\ISCC.exe`.
- Confirmed Visual Studio Community 2026 (18.7.3) with the C++ workload, MSBuild,
  CMake, Ninja, and the Windows SDK is detected by `flutter doctor`.
- Wrote the Windows packaging pipeline:
  - `scripts/build_windows_installer.ps1` — the orchestrator.
  - `scripts/bundle_windows_runtime.sh` — bundles Python + CHIRP next to the exe.
  - `installer/newchirp.iss` — Inno Setup installer definition.
  - Minor change to `scripts/update_chirp.sh` to honor `NEWCHIRP_PYTHON`.
- Downloaded and verified `cpython-3.13.15+20260807-x86_64-pc-windows-msvc-install_only_stripped.tar.gz`
  into `build_support\cache` (SHA256 checked against the release manifest).
- Fetched CHIRP master source into `build_support\chirp-master`.
- Built a debug Windows bundle:
  `build\windows\x64\runner\Debug\newchirp.exe`, with `python\` and `chirp\`
  bundled next to it.
- Compiled a debug installer: `build\NewChirp-Installer-1.0.0.exe` (~39 MB).
- Verified the debug app launches and the bundled Python 3.13.15 imports CHIRP.
- Refreshed OKF bundles (`okf_bundle`, `okf_bundle_scripts`) after the script edits.
- Updated `README.md` and `docs/SOFTWARE_ROADMAP.md`.

## Current status

The Smart App Control / WDAC blocker is resolved. After the reboot,
`gen_snapshot.exe` runs normally and the release build pipeline completed:

- `flutter build windows --release` succeeded.
- Python + CHIRP are bundled next to `newchirp.exe`.
- The app-local Visual C++ runtime is bundled next to `newchirp.exe`, so the
  installer does not depend on a separately installed VC++ redistributable.
- Inno Setup produced `build\NewChirp-Installer-1.0.0.exe` (release, ~33.8 MB).
- `newchirp.exe` reports version `1.0.0+1`; no debug CRT DLLs are in the bundle.

Two packaging script bugs were fixed in `scripts/build_windows_installer.ps1`:

- `cygpath.exe` is now found via `Git\usr\bin` when it is not next to `bash.exe`.
- The version is parsed with `$Version.Split('+')[0]` so the build metadata is
  stripped without a regex error.

## Remaining optional steps

- Install the release installer on a clean Windows machine/VM and confirm the
  app launches without extra runtimes.
- Re-run `scripts/update_chirp.sh` once `archive.chirpmyradio.com` is reachable,
  or apply the NewChirp UV-5G GMRS driver patch manually.
- Replace the placeholder Windows `.ico`; see `docs/SOFTWARE_ROADMAP.md`.
- Implement real COM-port enumeration on Windows (currently `COM1`-`COM4`).

## Useful commands / paths

- Flutter for Windows releases: 3.44.2 (`C:\flutter-3.44.2\bin\flutter.bat`)
- Git Bash (for the runtime bundler): `C:\Program Files\Git\bin\bash.exe`
- Inno Setup: `C:\Users\rlopez\AppData\Local\Programs\Inno Setup 6\ISCC.exe`
- App bundle (debug): `build\windows\x64\runner\Debug`
- Release bundle will be at: `build\windows\x64\runner\Release`
- Installer output: `build\NewChirp-Installer-<version>.exe`

## Optional follow-ups (not blocking the build)

- The CHIRP source was fetched from `codeload.github.com` because
  `archive.chirpmyradio.com` was unreachable from this machine. That fallback
  does not apply the NewChirp UV-5G GMRS driver patch; re-run
  `scripts/update_chirp.sh` once the archive is reachable, or apply the patch
  manually.
- The Windows `.ico` is still the Flutter default / placeholder; branding work is
  listed in `docs/SOFTWARE_ROADMAP.md`.
- COM-port discovery on Windows is still a placeholder (`COM1`–`COM4`), not real
  enumeration.
