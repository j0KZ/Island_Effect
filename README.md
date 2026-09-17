# Island Effect

*[English](README.md) · [Español](README.es.md)*

Turns the MacBook notch into an interactive island, in the spirit of
[NotchNook](https://lo.cafe/notchnook), but native, self-built and unlicensed.

A macOS app in Swift + SwiftUI with no external dependencies. It lives in the
menu bar (`LSUIElement`), draws a floating panel over the notch and expands on
hover.

![Island Effect open, showing the player](docs/preview.png)

## What it does

**An island that expands**
- At rest it is indistinguishable from the notch. Hovering opens it with a
  Dynamic-Island-style spring; leaving closes it.
- Click the notch: it stays open while you work inside; click again to close.
- When open, the panel **hangs below the menu bar**: only the notch occupies
  that row, so your other apps' icons stay visible.
- The window only accepts clicks while the pointer is over the island
  (`ignoresMouseEvents`): everything else reaches the menu bar as if the island
  weren't there.
- **System Liquid Glass** (`glassEffect`, macOS 26) tinted with the dominant
  colour of the artwork; on macOS 14–15 it falls back to `NSVisualEffectView`.
- On top of that, the panel takes a **colour wash from the cover art itself**:
  the artwork shrunk to 6×6 and blown back up, which interpolation turns into a
  gradient of the record's colours. It is the trick behind Apple Music's
  background and costs the same as drawing a 36-pixel image.
- A specular outline all the way around, with a halo, brighter along the bottom
  edge. It is what lets you find the island when the menu bar is all black, and
  it is adjustable from 0 to 100 % in Preferences. It is drawn slightly outside
  the notch cutout: there are no pixels inside it, so nothing would show.
- Inverted top corners, to blend into the screen edge.
- On **notchless displays** it becomes a handle centred under the menu bar,
  with the same behaviour.
- Multi-monitor: follows the screen the pointer is on (configurable).

**Notices** (a small pill hanging under the notch, never covering the menu bar)
- Track change: artwork, equalizer, elapsed time and a progress line along the
  bottom edge. It waits for the artwork before appearing, so it never flashes
  colourless.
- Charger plugged in or unplugged.

Volume and brightness deliberately have no notice: macOS already shows its own,
and duplicating them cost a permanent poll for nothing.

**Music** — Apple Music and Spotify, each toggled separately (turning off the
one you don't use saves a query and an automation prompt)
- Artwork, title, artist, scrubbable progress bar, previous/play/next and
  system volume.
- Clicking the artwork opens the source app.

**File shelf**
- Drop files onto the notch and they stay there. Drag them back out wherever
  you want, or use open / show in Finder / copy path.
- Persists across sessions.

**Screenshot tray**
- Every screenshot lands on the shelf by itself, as a thumbnail with a countdown
  over it. Drag it where it was going and it leaves; if you never use it, it
  clears itself after five minutes (1 to 30, configurable).
- macOS already shows its thumbnail in the bottom-right corner, but it lasts
  five seconds, only shows the last one and leaves nothing behind. This one
  waits, and stacks up.
- To keep one, drag it back onto the notch: the countdown goes away and it
  becomes an ordinary shelf item.
- Finds screenshots wherever you configured them (`defaults write
  com.apple.screencapture location`), not just on the Desktop. Screen recordings
  from ⇧⌘5 included.

**How you use it**
- Hover the notch to open it.
- Click: it stays open; click again to close.
- Drag files onto the notch and they go to the shelf.

There are no scroll gestures for volume or track skipping: the Mac keyboard
already does that, and keeping them meant a global scroll monitor that woke the
process on every scroll in the system.

**Preferences** (the island's gear, or the menu bar item)
- Open size (content compacts itself at short heights), corner radius, extra
  width at rest and outline.
- Open delay, haptics, which screen to follow, open at login and hiding the
  menu bar icon (with a quit button right there).
- Which modules you want (player, music sources, shelf) and which notices, with
  their duration. Leave a single module on and the tab bar disappears by itself.

Four tabs: General, Appearance, Modules and About.

## Install

```bash
./build.sh --install
```

Builds it, assembles `Island Effect.app`, signs it ad-hoc, copies it to
`/Applications` and launches it. Without the flag it only builds into `build/`;
with `--run` it runs it from there.

Requires macOS 14 or later and Xcode's Command Line Tools (`swift`). Building on
your own Mac is also what keeps Gatekeeper out of the way: the app is ad-hoc
signed and not notarised, so a prebuilt copy downloaded from elsewhere would be
quarantined.

## Permissions

Just one:

| Permission | What for | When |
|---|---|---|
| Automation (Music / Spotify) | Read and control playback | The first time a player is running |

It is not mandatory: without it the app still works, you just lose the player,
and the Music tab offers a shortcut to Settings to grant it. If you only use one
of the two players, turn the other off in Modules and macOS will never ask about
it.

It does **not** request accessibility, screen recording, camera, microphone,
location, contacts or calendar, and uses no API that would require them. It is
not sandboxed either, so the shelf reads the files you drop on it without
further ceremony (macOS may still ask about Desktop, Documents or Downloads the
first time a file from those folders is touched, as it would for any app).

## Languages

English and Spanish. The app follows the system language and falls back to
English for anything else. Strings live in `Resources/en.lproj` and
`Resources/es.lproj`; the keys are the English text itself, so adding a language
is copying a `.lproj` folder and translating it.

## How it is built

| File | Role |
|---|---|
| `NotchPanel.swift` | Borderless `NSPanel` above the menu bar, click-through outside the island |
| `NotchController.swift` | Position, hover, notices, multi-monitor, click pass-through |
| `NotchViewModel.swift` | State (at rest / notice / open) and the sizes of each |
| `NotchShape.swift` | The notch at rest and the expanded island (notch + hanging panel) |
| `RootView.swift` | Background, outline, notice pill and open panel |
| `MediaManager.swift` | Now playing and control: distributed notifications + AppleScript |
| `MusicView.swift` | The player, in three densities depending on panel height |
| `ShelfStore.swift` / `ShelfView.swift` | File shelf and screenshot tray |
| `ScreenshotWatcher.swift` | Watches the screenshot folder (`DispatchSource`) |
| `SystemMonitors.swift` | Volume (CoreAudio, on demand) and battery (IOKit) |
| `Components.swift` | Shared pieces: artwork, slider, equalizer, buttons |
| `SettingsView.swift` | Preferences + login item |
| `Debug.swift` | Optional log and test hooks (`ISLAND_*`) |

### Performance

Measured on a MacBook Pro M5 Pro, averaging real CPU time (delta of `cputime`
over wall clock; `ps %cpu` is useless here, it averages from process start and
includes the launch spike).

| Scenario | CPU | Memory |
|---|---|---|
| **At rest**, no notices | **0.40 %** | 72 MB |
| At rest with one track change in the window | 0.93 % | 72 MB |
| Animated track pill | 1.35 – 3.15 % | 76 MB |
| Island open, quiet screen behind | 1.63 % | 73 MB |
| Island open, changing content behind | 5.04 % | 71 MB |
| *(reference: before optimising, at rest)* | *5.33 %* | *125 MB* |

Cold start: **~130 ms** from launch to the island mounted and listening (three
runs: 128, 129, 130 ms). Binary 1.3 MB, bundle 1.6 MB, 10 threads.

Both island-open rows are the same code: the translucent material re-samples
whatever is behind it every time that changes, so over a quiet desktop it costs
a third of what it costs over a terminal spewing text. That is inherent to
anything translucent, macOS included.

Measuring "at rest" while actually using the Mac gives misleading numbers: the
island really does open every time the pointer brushes the notch. The figures
above were taken after checking in the log that there were zero openings during
the window.

What changed:

- **No `osascript` at rest.** Music and Spotify publish a distributed
  notification on every track change with the metadata inside; before, a whole
  `osascript` process was spawned every second. It only polls while the island
  is open (to advance the progress bar) and as a widely spaced safety net. If a
  player turns out not to publish notifications, the app detects it and goes
  back to polling more often.
- **No volume or brightness watching.** Two permanent polls to duplicate
  notices the system already gives. Worse for brightness: the Mac's automatic
  ambient adjustment makes constant micro-changes, so the pill was popping up on
  its own several times a minute.
- **No global scroll monitor.** Scroll gestures over the notch required
  listening to every scroll event in the system; they were dropped as useless
  (the keyboard already does that) and that constant wake-up went with them.
- **Battery through an IOKit notification** instead of a 5 s poll: the charging
  notice no longer arrives five seconds late, and another timer disappears.
- **Adaptive pointer polling**: 8 Hz away from the top edge, 30 Hz near the
  notch or with the island open, instead of a constant 60 Hz, with an early exit
  on the hot path. The real work is event-driven; the timer is only the safety
  net for full-screen apps.
- **The outline is rasterised** (`drawingGroup`): its blurs were recomputed
  every frame and with the pill animating the CPU went over 15 %. The glass
  stays outside that texture because it does not survive a `drawingGroup`.
- **Core Animation equalizer** instead of `TimelineView`, so the view is not
  re-evaluated twenty times a second.

### Known limitations

- Now playing only covers **Music and Spotify**. macOS 15.4 closed the private
  `MediaRemote` framework to apps without Apple entitlements, so there is no
  public way to read what a browser is playing.
- The native macOS volume/brightness HUD still appears; the island complements
  it, it does not replace it.
- Only tested on macOS 26 with Apple Silicon. The declared minimum is macOS 14
  and the compiler guarantees nothing newer is used without an availability
  guard, but nobody has run it on Sonoma, Sequoia or an Intel Mac.
- Black-and-white cover art tints the panel grey, because that is what the cover
  is. Correct, if surprising the first time.

### Debugging

```bash
ISLAND_DEBUG=1 ISLAND_LOG=/tmp/island.log open -n build/Island\ Effect.app
```

`ISLAND_TAB=music|shelf` forces the initial tab, `ISLAND_SETTINGS=1` opens
Preferences on launch, `ISLAND_DEMO=1` fires a test notice and `ISLAND_OPEN=1`
opens the island pinned.

## Licence and credit

Made by **j0KZ** — [github.com/j0KZ](https://github.com/j0KZ).
Released under the MIT licence (see [LICENSE](LICENSE)): use it, modify it and
distribute it, keeping the copyright notice.

The credit also appears inside the app, in Preferences › About, and in the
bundle's `NSHumanReadableCopyright` (what Finder shows in Get Info).
