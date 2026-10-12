## Sandclock 1.0.0

Native Mac menu bar countdown showing days, hours, minutes, and seconds.

- Sand flows behind the digits and settles using a column model shared with the curved hourglass.
- Calendar date picker, separate time control, and timezone selection.
- Empty optional name field with no fallback name.
- Percentage-based urgency colours and “Hope you made it.” at completion.
- Saves settings locally, respects Reduce Motion at launch, and uses no network services.
- Cached menu bar images refresh with the clock once per second. The larger animation runs at 12 fps only while its popup is visible.

Download the ZIP, unzip it, move Sandclock.app to Applications, and open it. This release is for Apple silicon, targets macOS 13 or later, and is ad-hoc signed rather than Apple-notarized. macOS may require approval under Privacy & Security for the downloaded copy.

Automated checks passed for timer arithmetic, sand volumes and bounds, percentage thresholds, date/time and timezone handling, and the completion message. A short menu-bar-only measurement on the development Mac was about 3.1% CPU over 10 seconds after the redraw changes. Real-world battery use and all macOS releases have not been benchmarked.
