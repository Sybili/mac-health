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

The automatic checks take about 3 seconds. The hands-on display and speaker
tests take about a minute. Skip them with `--quick`.

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

### Hands-on (you look and listen, then answer y/n)

- **Display:** the screen turns white, black, red, green, blue and gray, full
  screen with no menu bar or Dock. Look for dead or stuck pixels, spots, stains
  and uneven backlight. Click or press any key for the next colour, Esc to stop.
- **Speakers:** chimes on the left speaker only, then the right speaker only,
  then a rising tone from 60 Hz to 10 kHz on both, which makes crackling,
  buzzing and rattling easy to hear. If headphones or AirPods are connected,
  the test asks you to disconnect them first. If the volume is muted or very
  low, it is raised to 60 % for the test and restored afterwards.

Every hands-on step can be repeated (`r`) or skipped (`s`). Skipped tests are
listed as "Not tested" in the result and don't change the score.

## The result

At the end it prints:

- a **health score (0-100)** with a grade (Excellent / Good / Fair / Poor / Bad),
- a **verdict**: blockers always mean "do not buy (yet)",
- every **deduction**, so you can see why points were lost,
- what was **not tested**,
- a **rough battery outlook**: years until the battery hits 80 % at the wear rate so far,
- a short **manual checklist** for what a script cannot test (keys, ports, body).

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
| Speaker test: left or right speaker failed | -10 each |
| Speaker test: crackling, buzzing or rattling | -10 |
| Kernel panics: 1 / 2-3 / 4+ | -5 / -10 / -20 |
| SIP disabled | -10 |
| Possible MDM-bypass traces | -15 |
| Configuration profiles installed | -5 |
| Thermal warning | -5 |

## Recommended routine at the meetup

1. Run the check on the seller's account, including the display and speaker tests.
2. Do the manual checks the script prints (every key, every port, the body).
3. Seller signs out of their Apple Account, then you run the check again
   (`--quick` is enough). Activation Lock must say **Disabled**.
4. Seller erases the Mac in front of you:
   System Settings > General > Transfer or Reset > Erase All Content and Settings.
5. Check the serial number at [checkcoverage.apple.com](https://checkcoverage.apple.com).

## Privacy and safety

- **Nothing installed, nothing kept.** The automatic checks only read. The
  hands-on tests open a full-screen window and play sounds generated in memory;
  no files are written. A raised volume is put back when the test ends.
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
| `--quick` | Skip the hands-on display and speaker tests |
| `--no-color` | Plain output |
| `--help` / `--version` | Usage / version |

## Limits

- It reads what macOS reports plus what you see and hear in the tests. It cannot
  find sticky keys, dents, liquid damage or a port that is loose but still detected.
- SSD wear (percentage used, data written) needs `smartctl`, which is rarely installed.
- The battery outlook is a straight-line estimate from wear so far, so treat it as rough.
- For a fuller guided test (every key, ports, lid sensor) with a PDF report,
  [Aman Check](https://github.com/MidZai/aman_check) is a good native app to use alongside this.
