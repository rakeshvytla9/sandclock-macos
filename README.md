# Sandclock

A native Mac menu bar countdown with sand moving behind the digits, an animated hourglass, and a calendar for choosing your deadline. Built with Swift and AppKit, with no third-party dependencies or accounts.

![Sand flowing behind the countdown](docs/images/menu-bar.gif)

## Download

Get **Sandclock-macOS-arm64.zip** from the [latest release](https://github.com/rakeshvytla9/sandclock-macos/releases/latest).

1. Unzip the download and move **Sandclock.app** to Applications.
2. Open it. On first launch, choose a date from the calendar and set the time and timezone. The name is optional and starts empty.
3. Click **Start the clock**. The countdown lives in the menu bar, with days, hours, minutes, and seconds.
4. Click the countdown to open the hourglass or edit the deadline. Right-click it for a compact edit/quit menu.

The release targets **Apple silicon Macs with macOS 13 or later**. It is ad-hoc signed and is **not Apple-notarized**. macOS may block the first launch of a downloaded copy; use **System Settings → Privacy & Security → Open Anyway** if that happens. No paid Apple developer account is needed to build or run it locally.

The app has no Dock icon. It does not start automatically after reboot; add it in **System Settings → General → Login Items** if you want that.

## Features

- Exact days, hours, minutes, and seconds in the menu bar.
- Grains enter from the left and settle to the right behind the digits. The text stays on top with a contrasting halo, and the graphic uses the countdown's existing width.
- Both the menu bar and the hourglass use the same small-column sand model. Neighbouring columns exchange sand when their visual slope is too steep. The hourglass's column capacities follow the curved glass walls.
- The visible flow stays near four grains per second. Each grain contributes a smaller fraction of the container on longer countdowns, so the fill reflects the countdown's elapsed percentage and finishes at the deadline.
- Calendar date picker, separate time control with seconds, and timezone selection. India time (IST) is selected initially; UTC and the Mac's timezone are available too.
- The name field starts empty, stays empty if saved without a name, and has no default motivational text.
- Gold above 25% remaining, amber above 10% through 25%, and red for the final 10%. At completion the colour returns to gold and the message is **“Hope you made it.”**
- Deadlines and names are saved locally between launches. The timer catches up from the actual target date after sleep; it stays at zero after completion.
- The menu bar animation runs at 8 fps. The hourglass runs at 24 fps only while its popup is open. **Reduce Motion** is respected at launch.
- No network calls, telemetry, microphone/camera access, or notifications. There is no completion alarm sound.

![Calendar and time controls](docs/images/calendar.png)

## Build

Install Apple's Xcode Command Line Tools, then run:

```sh
git clone https://github.com/rakeshvytla9/sandclock-macos.git
cd sandclock-macos
./scripts/build.sh
open dist/Sandclock.app
```

The script builds for the current Mac's architecture, ad-hoc signs the app, runs its checks, and creates a ZIP in `dist/`. To select an architecture explicitly:

```sh
./scripts/build.sh arm64
./scripts/build.sh x86_64
```

The published binary and UI were tested on Apple silicon. An Intel build path is provided, but Intel runtime behaviour has not been verified. Cross-compiled checks are skipped until run on matching hardware.

## Checks

```sh
dist/Sandclock.app/Contents/MacOS/Sandclock --self-test
```

Checks cover time-unit boundaries, fractional seconds, expired deadlines, progress, deadline-scaled grain arrivals, volume conservation, sideways spreading, rectangular and curved container bounds, percentage colour boundaries, the completion message, calendar/time merging, and nonexistent daylight-saving times. They do not open the UI or change a saved deadline.

Native preview exports use a sample countdown without changing local settings:

```sh
dist/Sandclock.app/Contents/MacOS/Sandclock --render-setup dist/calendar.png
dist/Sandclock.app/Contents/MacOS/Sandclock --render-preview dist/hourglass.png
dist/Sandclock.app/Contents/MacOS/Sandclock --render-complete dist/complete.png
dist/Sandclock.app/Contents/MacOS/Sandclock --render-menubar dist/menu-bar.gif
```

## How the sand works

The visible grains follow simple horizontal travel and downward acceleration. The accumulated pile is a height field: incoming volume is deposited into columns, and excessive slopes transfer volume to neighbours. This is a stylized approximation, with slopes chosen for a small display; it does not simulate every grain's collisions, friction, or pressure.

Long countdowns scale down the volume represented by each visible grain. Only a small number of airborne and recently landed grains are drawn. Large elapsed-time jumps are reconstructed in bounded batches rather than replaying months of arrivals. Editing a deadline starts a new interval for the sand and progress display.

No numerical CPU or battery-use claim has been benchmarked. Compatibility across every macOS release and long-duration sleep/wake behaviour have not been exhaustively tested.

The app's local preferences use `local.sandclock.countdown`. Saved countdown settings are not included in this repository or the release ZIP.
