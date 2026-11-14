---
name: darling-app-compat-scan
description: Estimate what a macOS application needs from Darling - mount its DMG, statically list imported system libraries and symbols missing from the Darling install, run it in Darling to find the first real blocker, and report the findings. Use when asked whether an app runs in Darling, what is missing for it, or to triage an app's failure.
---

# Scanning a macOS app for missing Darling APIs

The goal is a ranked list of what blocks an app, not a list of every gap.
Combine two views:
- a **static scan**, which shows everything the app could need;
- a **real run**, which shows what stops it first.

## Rules
- Only read binary metadata: load commands and symbol tables via `llvm-objdump --macho` and `llvm-nm -m`. No disassembly of Apple binaries (AGENTS.md section 7).
  - The app's own code may be inspected for which APIs it calls. Don't use it to learn how Apple implements them.
- Downloads are untrusted:
  - put each in its own new directory in the scratchpad;
  - keep scripts elsewhere;
  - run Python with `-I`.
- Findings describe general API gaps. Never propose app-specific workarounds (AGENTS.md section 1).
- Use the universal or x86_64 build on an x86_64 host. An arm64-only DMG is useful only on an arm64 Darling build.

## 1. Get and mount the app
```
D=<scratchpad>/<app>; mkdir -p $D/dl $D/mnt
curl -sSfL -o $D/dl/app.dmg <url>
darling-dmg $D/dl/app.dmg $D/mnt &      # FUSE; unmount with fusermount -u $D/mnt
```
- `.zip`: use `unzip` into `$D/mnt`.
- `.pkg`: use `xar -xf`, then `cpio` on the Payload.
- Check the slices with `llvm-objdump --macho --universal-headers <main executable>`.

## 2. Static scan
```
python3 -I <this skill>/scripts/scan_app.py $D/mnt/<App>.app \
        --arch x86_64 --json $D/scan.json [--root <installed Darling tree>] [--max 40]
```
- It checks every Mach-O in the bundle against the installed Darling (default root: `<prefix>/libexec/darling` of the `darling` launcher on `PATH`, else `/usr/local/libexec/darling`), following re-exports. This is roughly 1 minute for 350 files.
- It sorts the output with libraries Darling lacks first, then those with the most missing **strong** imports.
- **A missing strong import** makes dyld refuse to load that image. Missing **weak** imports only become NULL.
- **Which file imports it matters.**
  - The main executable and frameworks loaded at launch block startup.
  - Plugins, helper apps (crash reporters, updaters) and bundled frameworks such as Growl, Sparkle or Breakpad only matter when used.
  - Group the findings by that.
- `MISSING` means a whole library or framework isn't installed.
- **The scan only sees link-time imports.** It can't see:
  - `dlopen`/`dlsym`, `NSClassFromString`, `objc_msgSend` to unimplemented methods;
  - constants that exist but have wrong values;
  - behaviour gaps.

  The run in step 3 covers those.

## 3. Run it in Darling
- Make sure Darling is running the current install (see the darling-guest-testing skill), and that Xvfb `:99` with xfwm4 is up for GUI apps.
- The app's files are visible in the guest under `/Volumes/SystemRoot/<host path>`.
- Write the output to a file. Never pipe `darling shell` output. Always put a timeout on the run.

```
timeout -s KILL 120 darling shell env DISPLAY=:99 /Volumes/SystemRoot$D/mnt/<App>.app/Contents/MacOS/<Exe> </dev/null > $D/run1.out 2>&1
```
- Many apps have a CLI or headless mode (for example `--intf dummy`, `--help`, `--version`). Try that first to separate core loading from GUI failures.
- **Read the first fatal error:**
  - `Symbol not found: _X ... Referenced from: <image>` names a missing export and the image that needs it.
  - `Library not loaded` names a missing library.
  - An ObjC `unrecognized selector` names a missing method.
- **Fix-forward to see the next blocker:** a load failure in a plugin often only disables that plugin.
  - Note what still works: does the main program initialise? Do other plugins load?
  - Then try to reach the next stage: the GUI plugin, opening a file, playback.
- **Runtime errors from existing APIs** (OSStatus codes, `kAudioHardware...Error`) are Darling bugs in implemented code. Note them with the API, the arguments and the error, and find the source location in the Darling tree.
- For hangs, take a backtrace of the stuck process from the guest's lldb, if available, rather than guessing.
- Afterwards, kill leftover processes from your own run. List any you kill.

## 4. Ranking and estimate
Order the findings as:
1. what blocks launch;
2. what blocks the main window or core feature;
3. secondary features (screen capture, notifications, updater);
4. bundled third-party helpers.

For each gap, give:
- the framework;
- the symbols;
- whether Darling has the framework at all, or only lacks those symbols;
- a rough size: constant, stub-able, small function, or subsystem.

Separate "missing export" from "exists but misbehaves".

## 5. Report
Write the findings into a report for the user. Don't open GitHub issues.

Include:
- the app, its version, the download URL and the slice tested;
- the commands used for the scan and the run, so the result can be reproduced;
- the first blocker, with the exact error text;
- missing symbols for each framework, with the image that imports each;
- runtime errors, with source locations in the Darling tree;
- a suggested order of work, and which parts are general API work rather than app-specific.

Don't paste the app's binary contents. Keep it to symbol names and error messages.

## 6. Clean up
- `fusermount -u` the mount.
- Delete large downloads once the report is done, unless further work is planned.
