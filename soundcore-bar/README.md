# SoundcoreBar

A macOS menu bar app for Soundcore earbuds, built on the `openscq30` CLI. Made for the R50i NC (A3959).

- Noise control: Noise Cancelling (Adaptive, Manual 1-5, Scene), Transparency, Off
- EQ presets, an 8-band custom EQ editor, and saved custom EQs
- Battery levels, a dimmed menu bar icon while disconnected, and a popup when the earbuds connect
- Open at Login and a choice of menu bar icon

## Build

Requires macOS 14+, Rust, and the Xcode Command Line Tools. The macOS connection backend comes from upstream PR #372, which this branch is based on.

```bash
cargo build --package openscq30-cli --profile release-fast
./soundcore-bar/scripts/build-app.sh
```

The app is written to `soundcore-bar/build/SoundcoreBar.app`. Set `OPENSCQ30_BIN` to use a CLI binary from elsewhere.

Register the earbuds with openscq30 once (this is not Bluetooth pairing):

```bash
target/release-fast/openscq30 paired-devices add --mac-address <MAC> --model SoundcoreA3959
```

## How it works

The app bundles the CLI next to its own executable and runs it for each read or change, so the CLI inherits the app's Bluetooth permission (`NSBluetoothAlwaysUsageDescription`). Without that, macOS kills a bare CLI process that opens Bluetooth.

The earbuds accept one control session at a time: while the Soundcore phone app is connected, commands from the Mac time out.

## Product images

The connected popup shows `Resources/DeviceLeft.png` and `Resources/DeviceRight.png` when present, and an SF Symbol otherwise. They are git-ignored because they are Anker's renders. The Soundcore app downloads them from `https://d2htfo7ft368vg.cloudfront.net/media/prod/a3959/<colour>/a3959_<colour>.zip`; use the `*_device_l.png` and `*_device_r.png` files.
