# mac-check

A quick health check for a **used Apple silicon Mac (M1 and later) before you
buy it**, for example when meeting a seller from eBay Kleinanzeigen. Open
Terminal on the seller's Mac, paste one line, and get a health score plus a
buy / don't-buy verdict.

```bash
curl -sL https://sybili.github.io/mac-health | bash
```

Fallback (same script, straight from GitHub):

```bash
curl -sL https://raw.githubusercontent.com/Sybili/mac-health/main/mac-check.sh | bash
```

> Open Terminal with `Cmd + Space`, type "Terminal", press Enter.

The automatic checks take about 3 seconds. The hands-on tests (screen,
keyboard, camera, speakers, microphone) take about 3 minutes. Skip them with
`--quick`.

## What it checks

### Automatic

| Area | Checks |
|---|---|
| **Machine** | Model and release year, chip, memory, storage, serial number, macOS version, date macOS was set up |
| **Locks & ownership** | Activation Lock, Apple Account / Find My, MDM enrollment, Apple Business Manager (DEP) registration, MDM-bypass traces, configuration profiles, System Integrity Protection, virtual machine |
| **Battery** | Condition, maximum capacity (and mAh), cycle count vs. rated cycles, battery age from the gauge, usage rate, failure flag, temperature, charger |
| **Storage** | SSD model, SMART status (plus wear and data written if `smartctl` happens to be installed) |
| **Built-in hardware** | Internal display, keyboard/trackpad, camera, Wi-Fi, Bluetooth, speakers, microphone (does macOS detect them?) |
| **Stability** | Kernel panics in the logs, thermal throttling |

### Hands-on (you look, press and listen)

- **Display:** the screen turns white, black, red, green, blue and gray, full
  screen with no menu bar or Dock. Look for dead or stuck pixels, spots, stains
  and uneven backlight. Click or press any key for the next colour, Esc to stop.
- **Keyboard:** a window shows the built-in keyboard in its real layout
  (US ANSI or European ISO, with German labels on a German keyboard). Press
  every key once; each one turns green when macOS registers it, including fn,
  both Shift, Option and Command keys, Caps Lock and the arrows. Hold fn for
  F1 to F12. The window closes by itself when every key is green, and the script
  lists any key that never registered.
- **Camera:** a window shows the live image from the built-in camera for up to
  30 seconds, so you can check sharpness and colours and that the green light
  turns on.
- **Speakers:** chimes on the left speaker only, then the right speaker only,
  then a rising tone from 60 Hz to 10 kHz on both, which makes crackling,
  buzzing and rattling easy to hear.
- **Microphone:** records 4 seconds while you talk, measures the level (a dead
  microphone is detected automatically), then plays the recording back.

If headphones, AirPods or an iPhone are the current audio device, the tests ask
you to disconnect them first. A muted or very low volume is raised for the
tests and restored afterwards. Every step can be repeated (`r`) or skipped
(`s`). Skipped tests are listed as "Not tested" and don't change the score.

The first camera and microphone test on a Mac shows the macOS prompt
"Terminal would like to access the camera / microphone". Click **Allow**. If
access was denied before, the test is skipped with a pointer to Photo Booth.

## The result

At the end it prints:

- a **health score (0-100)** with a grade (Excellent / Good / Fair / Poor / Bad),
- a **verdict**: blockers always mean "do not buy (yet)",
- every **deduction**, so you can see why points were lost,
- what was **not tested**,
- a **rough battery outlook**: years until the battery hits 80 % at the wear rate so far,
- a short **manual checklist** for what a script cannot test (trackpad, Touch ID, ports, Wi-Fi).

### Blockers

These make the Mac unusable or not really yours, so the verdict is always
**DO NOT BUY (yet)** while any of them is present:

- Activation Lock on (seller still signed in with Find My)
- MDM enrollment or Apple Business Manager registration (company-owned Mac)
- MDM bypass detected (Apple enrollment servers blocked in `/etc/hosts`)
- SSD reporting a SMART failure
- Running inside a virtual machine

Activation Lock will show as a blocker on almost every seller's Mac at first.
That is expected: ask the seller to sign out of their Apple Account, run the
check again, and it must say **Disabled**.

### Scoring

The score starts at 100 and loses points per finding. Battery findings together
cost at most 35 points, because a battery can be replaced.

| Finding | Points |
|---|---|
| Battery: condition "Service Recommended" | -25 |
| Battery: capacity 85-89 % / 80-84 % / below 80 % | -5 / -12 / -25 |
| Battery: cycles at 30-60 % / 60-80 % / 80-100 % / over 100 % of rated | -3 / -8 / -15 / -20 |
| SSD SMART failure | -40 |
| Internal display / keyboard+trackpad not detected | -30 / -20 |
| Wi-Fi / Bluetooth / camera not detected | -15 / -10 / -10 |
| Speakers / microphone not detected | -5 each |
| Display test: defects seen | -15 |
| Keyboard test: a main key never registered | -15 |
| Keyboard test: an F-key never registered | warning only (macOS can claim F-keys for shortcuts) |
| Camera test: image or light faulty | -10 |
| Speaker test: left or right speaker failed | -10 each |
| Speaker test: crackling, buzzing or rattling | -10 |
| Microphone test: no sound picked up / recording unclear | -15 / -10 |
| Kernel panics: 1 / 2-3 / 4+ | -5 / -10 / -20 |
| SIP disabled | -10 |
| Possible MDM-bypass traces | -15 |
| Configuration profiles installed | -5 |
| Thermal warning | -5 |

## Recommended routine at the meetup

1. Run the check on the seller's account, including the hands-on tests.
2. Do the manual checks the script prints (trackpad, Touch ID, every port, Wi-Fi).
3. Seller signs out of their Apple Account, then you run the check again
   (`--quick` is enough). Activation Lock must say **Disabled**.
4. Seller erases the Mac in front of you:
   System Settings > General > Transfer or Reset > Erase All Content and Settings.
5. Check the serial number at [checkcoverage.apple.com](https://checkcoverage.apple.com).

## Privacy and safety

- **Nothing installed, nothing kept.** The automatic checks only read. The
  hands-on tests open windows and play sounds generated in memory. The
  4-second microphone recording goes to a temporary folder that is deleted
  right after playback, also on Ctrl-C. A raised volume is put back when the
  tests end.
- **Camera and microphone permission.** macOS remembers the "Allow" for
  Terminal until the Mac is erased, or until it is removed in System Settings >
  Privacy & Security.
- **Offline.** The script makes no network requests; only the `curl` that downloads it does.
- **No admin password.** Runs as the logged-in user.
- The Apple Account e-mail address is never printed, only whether someone is signed in.
- Works with the stock `/bin/bash` 3.2 and reads the language-independent keys
  from `system_profiler -json`, so a German or any other system language works.
- Apple silicon only. On an Intel Mac it stops with a message.

Read the source before you run it on someone else's Mac: it is one file,
[`mac-check.sh`](mac-check.sh).

## Options

```bash
curl -sL https://sybili.github.io/mac-health | bash -s -- --quick
curl -sL https://sybili.github.io/mac-health | bash -s -- --no-color
```

| Option | Effect |
|---|---|
| `--quick` | Skip the hands-on tests |
| `--no-color` | Plain output |
| `--help` / `--version` | Usage / version |

## Limits

- It reads what macOS reports plus what you see and hear in the tests. It cannot
  find sticky or mushy keys, dents, liquid damage or a port that is loose but
  still detected.
- macOS uses some F-keys for system shortcuts (F11 shows the desktop), so those
  may not reach the keyboard test. They are reported as a warning, not a fault.
- SSD wear (percentage used, data written) needs `smartctl`, which is rarely installed.
- The battery outlook is a straight-line estimate from wear so far, so treat it as rough.
- For a fuller guided test (trackpad, ports, lid sensor) with a PDF report,
  [Aman Check](https://github.com/MidZai/aman_check) is a good native app to use alongside this.
