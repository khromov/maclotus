# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Regenerate Xcode project from project.yml (required after adding/removing files)
xcodegen generate

# Build the macOS status bar app (Debug — unsigned)
xcodebuild -project MacLotus.xcodeproj -scheme MacLotus -configuration Debug build

# Build the CLI tool (Debug — unsigned)
xcodebuild -project MacLotus.xcodeproj -scheme maclotus-cli -configuration Debug build

# Release build: signed + notarized DMG (requires Developer ID cert + stored notarytool credentials)
./scripts/build-release.sh

# Release build without notarization (quick test)
./scripts/build-release.sh --skip-notarize

# Store notarization credentials (one-time setup)
xcrun notarytool store-credentials "MacLotus" --apple-id "your@email.com" --team-id "36S2252ZTN" --password "app-specific-password"
```

No test targets exist in this project.

## Architecture

Two targets share core BLE protocol files:

**macOS Status Bar App (`Sources/` directory)**
- `MacLotusApp.swift` — `@main` SwiftUI entry; bridges to `AppDelegate` via `@NSApplicationDelegateAdaptor`
- `AppDelegate.swift` — `NSStatusItem` + `NSPopover`; creates `BLEManager` and passes it as an `@EnvironmentObject`
- `BLEManager.swift` — `ObservableObject` wrapping `CoreBluetooth`; holds all lamp state locally (write-only BLE protocol means no read-back from device)
- `LampCommand.swift` — static factory for all 9-byte BLE packets (`7E … EF`)
- `BLEConstants.swift` — service/characteristic UUIDs and filtering rules
- `Views/MainPopoverView.swift` → `ConnectionView.swift` + `ControlsView.swift` — SwiftUI popover UI
- `Views/CLIHelpView.swift` — in-app sheet with CLI installation/usage instructions
- `Views/ClaudeHooksView.swift` — installs/uninstalls Claude Code hooks into `~/.claude/settings.json`; hooks change lamp color on Claude session events (SessionStart→yellow, UserPromptSubmit→green, Stop/Notification→orange, SessionEnd→off); merges into existing settings without clobbering other keys
- `PresetColor.swift`, `EffectMode.swift` — data types for UI color/effect pickers

**CLI (`CLI/` sources)**
- `main.swift` — `ArgumentParser` commands: `on`, `off`, `color <hex|preset>`, `colors`; supports `--device <name>` to target by device name
- `CLIBLEManager.swift` — synchronous BLE wrapper (blocks via `RunLoop`) for CLI use
- Shares `LampCommand.swift`, `BLEConstants.swift`, `PresetColor.swift`, `EffectMode.swift` with the app target

## BLE Protocol

All commands are 9-byte packets: `7E [payload bytes] EF`

| Command | Bytes |
|---|---|
| Init (send after connect) | `7E 06 83 0F 20 0C 06 00 EF` |
| Power on | `7E 07 04 FF 00 01 02 01 EF` |
| Power off | `7E 07 04 00 00 00 02 01 EF` |
| Set color (R G B) | `7E 07 05 03 R G B 10 EF` |
| Set brightness (1–100) | `7E 04 01 V 01 FF 02 01 EF` |
| Set effect mode | `7E 07 03 M 03 FF FF 00 EF` |
| Set effect speed (1–100) | `7E 07 02 V FF FF FF 00 EF` |

Characteristic selection mirrors `bluetooth.js`: prefer writable chars whose UUID contains `fff` or `ffe`; skip standard BLE services (1800/1801).

## App Icon

Icons live in `Sources/Assets.xcassets/AppIcon.appiconset/`. To regenerate from `logo.png` after it changes:

```bash
# Crop to square (adjust height/cropOffset to match logo dimensions)
sips --cropToHeightWidth <H> <H> --cropOffset 0 <X_OFFSET> logo.png --out /tmp/logo_square.png

# Generate all required sizes
for size in 16 32 64 128 256 512 1024; do
  sips -z $size $size /tmp/logo_square.png --out Sources/Assets.xcassets/AppIcon.appiconset/icon_${size}.png
done
```

`X_OFFSET` = `(width - height) / 2` to center-crop. Check dimensions first with `sips -g pixelWidth -g pixelHeight logo.png`.

## Key Notes

- Swift `switch` on `Int` ranges with negative values doesn't compile — use `if`/`else` chains instead
- Lamp state is tracked locally only (`@Published` vars in `BLEManager`); the device does not send state back
- Color and brightness sends are debounced 100ms via `DispatchWorkItem` to avoid flooding BLE
- Auto-reconnect on launch: last peripheral UUID is persisted in `UserDefaults` under `BLEConstants.lastPeripheralUUIDKey`
- Debug builds are unsigned (`CODE_SIGN_IDENTITY: "-"`, `CODE_SIGNING_REQUIRED: NO`); Release builds use Developer ID + hardened runtime (Team ID: 36S2252ZTN)
- CLI binary is embedded in `Contents/Resources/maclotus` via a post-compile script in the MacLotus target
