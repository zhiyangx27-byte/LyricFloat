<p align="center">
  <img src="Resources/LyricFloatIconMaster.png" width="144" alt="LyricFloat icon">
</p>

<p align="center">
  <a href="README.md">简体中文</a> | <strong>English</strong>
</p>

# LyricFloat

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![CI](https://github.com/zhiyangx27-byte/LyricFloat/actions/workflows/ci.yml/badge.svg)](https://github.com/zhiyangx27-byte/LyricFloat/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

LyricFloat is a native macOS menu bar app that displays customizable floating lyrics for Apple Music. It prioritizes synchronized LRC lyrics and supports conservative LRCLIB matching, manual lyric version selection, local LRC overrides, and per-track timing offsets.

## Features

- Native SwiftUI and AppKit menu bar app with no Dock icon
- Exact LRCLIB lookup, cleaned-metadata search, candidate scoring, and rejection of low-confidence matches
- Manual LRCLIB version selection with an option to return to automatic matching
- Local LRC import with priority over every online source
- Customizable font, size, line spacing, colors, opacity, alignment, and background
- Automatic discovery of installed fonts such as Arial, with a system rounded font fallback when the selected font is unavailable
- Native window dragging, resizing, pinning, click-through mode, and one-click recentering on the current display
- Support for multiple Spaces and full-screen apps, a global visibility shortcut, and launch at login
- Persistent manual hiding while lyrics continue refreshing in the background between tracks
- Simplified Chinese and English, following the macOS app language setting

## Requirements

- macOS 15 or later
- Apple Music
- A network connection for LRCLIB queries
- Swift 6 when building from source; Xcode 16 or later is recommended

## Quick Start

```bash
git clone https://github.com/zhiyangx27-byte/LyricFloat.git
cd LyricFloat
./script/build_and_run.sh
```

You can also open `LyricFloat.xcodeproj` in Xcode, select the `LyricFloat` scheme, and run it.

The first time LyricFloat reads the current track, macOS asks for permission to access Apple Music. If access was previously denied, open System Settings > Privacy & Security > Automation and allow LyricFloat to control Music.

### Build Commands

| Command | Purpose |
| --- | --- |
| `./script/build_and_run.sh` | Build and launch a Debug app |
| `./script/build_and_run.sh test` | Run all unit tests |
| `./script/build_and_run.sh build` | Build the Debug app only |
| `./script/build_and_run.sh release` | Build a universal arm64 and x86_64 Release app |
| `./script/build_and_run.sh install` | Build Release, install to `/Applications`, and launch |
| `./script/build_and_run.sh verify` | Build, launch, and verify that the process stays alive |

When full Xcode is unavailable, the script falls back to SwiftPM for the current Mac architecture. Set `LYRICFLOAT_DERIVED_DATA`, `LYRICFLOAT_SWIFT_BUILD_DIR`, or `LYRICFLOAT_INSTALL_DIR` to customize build and installation locations.

## Usage

1. Play a song in Apple Music.
2. Click the speech bubble icon in the menu bar to show or hide lyrics.
3. While unlocked, drag the lyric text to move the window. Move the pointer over the window to use the pin and resize controls in the lower-right corner.
4. Select any installed system font under Settings > Appearance > Lyric Font.
5. If automatic matching is not satisfactory, choose Select Lyric Version... from the menu.
6. If the window moves off screen, choose Move to Display Center from the menu.

The app follows the macOS language preference by default. You can set LyricFloat's language separately under System Settings > General > Language & Region > Applications.

## Lyric Priority

1. User-imported local LRC override
2. User-selected LRCLIB version
3. Local LRCLIB cache
4. Exact LRCLIB lookup
5. Cleaned-metadata LRCLIB search with conservative scoring
6. Plain lyrics supplied by Apple Music

Automatic matching returns no result rather than accepting a low-confidence candidate. Lower-scoring results remain available in the manual candidate list for the user to evaluate.

## Data and Privacy

The lyric cache, local overrides, manual selections, and per-track offsets are stored at:

```text
~/Library/Application Support/LyricFloat/lyrics.json
```

Preferences use the current user's `UserDefaults` and contain no developer-machine paths. LyricFloat does not upload playback history or use analytics services. LRCLIB queries send the current track title, artist, album, and duration. A damaged lyric store is preserved as `lyrics.json.corrupt`, after which the app continues with an empty store.

## Distribution

The `release` command builds a universal app for Apple Silicon and Intel Macs. Local repository builds use ad-hoc signing and are not signed with a Developer ID or notarized, so they are intended for source builds and personal use. Before distributing binaries to other users, configure your own Team and unique Bundle Identifier in Xcode, then complete Developer ID signing and notarization.

## Development

```bash
swift test
```

Tests cover LRC parsing, LRCLIB matching and rejection, caching and source priority, manual selection, preference persistence, font fallback, lyric window geometry, manual visibility behavior, and localization resource parity. CI runs the same SwiftPM test suite on a macOS runner.

## Limitations

- Apple Music is currently the only supported media source.
- Synchronized lyrics require LRCLIB or a user-imported LRC. The Apple Music fallback may provide plain lyrics only.

## License

[MIT](LICENSE)
