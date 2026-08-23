# NewChirp — Machine Setup

This project is shared across Linux, macOS, and Windows machines. The repository
stays identical everywhere; the only thing that's per-machine is the **Flutter SDK
path**, which is intentionally not committed (see `.gitignore`). Each machine
supplies its own SDK location and generates its own build files.

## 1. Get the code

```sh
git clone https://github.com/ricktek954/newchirp.git
cd newchirp
```

If you already have the repo, just `git pull` to stay in sync.

## 2. Install Flutter

Install a recent **stable** Flutter on this machine (the app requires Dart
`^3.10.8`). Either add `flutter/bin` to your `PATH`, or keep note of the absolute
path to the `flutter/` folder for step 3.

## 3. Open the project in VS Code

Open the `newchirp` folder in VS Code and install the **Flutter** (and Dart)
extension.

Point VS Code at your Flutter SDK by creating `.vscode/settings.json` in the
project root:

```json
{
  "dart.flutterSdkPath": "/path/to/your/flutter"
}
```

Replace the path with your own. This file is gitignored, so it stays local to
this machine and never affects anyone else.

If `flutter` is already on your `PATH`, you can skip this step. If VS Code
doesn't pick up the SDK, run **Flutter: Select Flutter SDK** from the command
palette, or reload the window.

## 4. Fetch dependencies

```sh
flutter pub get
```

## 5. Run the app

Run on this machine's platform:

```sh
# macOS
flutter run -d macos

# Linux
flutter run -d linux

# Windows
flutter run -d windows
```

That's it. The code and shared VS Code config (`launch.json`, `tasks.json`) sync
through git; each machine just provides its own SDK path and build artifacts.
