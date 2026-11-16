---
name: darling-guest-testing
description: Build a Darling change, install only what changed, restart the container and test it inside the guest - cross-compiling guest test programs on the host, running them with darling shell, GUI tests on Xvfb (X11) or headless sway (Wayland), measuring audio output, before/after comparison and cleanup of leftover processes. Use whenever a Darling change has to be verified at runtime.
---

# Testing a change inside Darling

The scripts are in `scripts/` next to this file; run them from inside the Darling checkout (or one of its submodules). They read:
- `DARLING_SRC` (default: the Darling checkout containing the current directory);
- `DARLING_BUILD` (default: the newest `build*/` in it with a `CMakeCache.txt`);
- `DARLING_ROOT` (default: `<prefix>/libexec/darling` of the `darling` launcher on `PATH`, else Darling's default `/usr/local/libexec/darling`).

## Ground rules
- **The installed Darling is shared:** only one agent at a time may install into it and run tests.
- **Never pipe `darling shell` output** (`| head`, `| grep`). Redirect to a file, then read the file.
- **Always** pass `</dev/null` and put a `timeout -s KILL` around a guest run, because a hung guest program keeps the shell blocked. `timeout` alone doesn't kill Darling programs; use `-s KILL`.
- **No `rm` inside the guest.** Clean up from the host, after shutdown.
- **Run the tests before the change as well as after.** A test that fails before and passes after is the evidence.
- **Never weaken or delete a failing test** to get a pass.

## 1. Build and install only what changed
```
scripts/rebuild.sh <Target> [<Target>...]       # e.g. AppKit CoreAudio
scripts/rebuild.sh -f <Target>                  # <target>/fast: skips dependency checks
```
The script:
1. builds the targets;
2. stops Darling;
3. runs `sudo -n cmake -P cmake_install.cmake` in each target's build directory;
4. starts Darling again.

The whole cycle takes seconds, against minutes for a top-level `make install`.

Use `-f` only when nothing the target links against has changed. If headers or a lower library changed, rebuild those targets too.

Do a full `make -j$(nproc)` and `sudo make install` only for:
- widely linked changes: libsystem_kernel/xnu, libc, dyld, shared headers, `cmake/` changes;
- the final test of a piece of work.

Never put a short timeout on a full install: an interrupted install invalidates the test.

**Submodules:** apply the change in the submodule checkout under `src/external/<repo>`. The build uses that tree directly.

## 2. Restart and leftovers
```
scripts/restart.sh          # shutdown, report leftovers, start (retries the first start)
scripts/leftovers.sh [-k]   # list (and with -k kill) mldr/darlingserver processes
```
- `darling shutdown` sometimes reports "not running" while a container launchd, its daemons or a hung test stay alive. They block installing and pile up over time.
- Kill only processes from your own runs, and list what you killed in your report.
- Right after a shutdown, the first `darling shell` can fail with "Cannot open mnt namespace file". `restart.sh` retries.
- **Don't** use `pgrep -f`/`pkill -f` with a plain pattern from a script: it can match, and kill, your own shell. Use `ps … | grep '[p]attern'`.

## 3. Guest test programs
There is no compiler inside the guest. Cross-compile on the host:
```
scripts/guest-cc.sh -o /path/t t.c
scripts/guest-cc.sh -a i386 -o /path/t32 t.c
scripts/guest-cc.sh -o /path/t t.m -framework Foundation -framework AppKit -fobjc-arc
scripts/guest-cc.sh -o /path/libx.dylib -dynamiclib -install_name @rpath/libx.dylib x.c
```
It uses:
- host clang with `-target <arch>-apple-macos<min>`;
- the **source-tree** SDK. The `build/Developer` copy lacks most headers.
- Darling's ld64 through `-B`;
- the subframeworks of each umbrella framework, such as `<AE/AE.h>` under CoreServices, added with `-iframework`;
- the **installed** Darling tree as a second `-syslibroot`. The SDK has headers but no link stubs for most frameworks or libobjc, so linking happens against the installed binaries. **Install before building tests that need new symbols.**
- `adhoc-sign` on the result.

Details:
- **`-D__DARWIN_ONLY_UNIX_CONFORMANCE=1`** is added for x86_64, because without it the link fails on `$UNIX2003` symbols. It must **not** be used for i386.
- The SDK's `<stdatomic.h>` doesn't work. Use the `__atomic_*` builtins.
- **Write tests from the documented contract.** Make each test print one clear PASS/FAIL line, or exit non-zero on failure, so before and after can be compared mechanically.
- **Keep test sources with the change** (for example `tests/` in the repo). The binaries are not committed.

## 4. Running in the guest
```
timeout -s KILL 120 darling shell /Volumes/SystemRoot/<abs host path>/t </dev/null > out.txt 2>&1; echo rc=$?
```
- Host files are visible in the guest under `/Volumes/SystemRoot`. Run test binaries from there.
- **The prefix (`$DPREFIX`, `~/.darling` by default) is an overlay:** files written into it from the host while the container runs are not reliably visible in the guest. To place a file in the guest:

  ```
  darling shell cp /Volumes/SystemRoot/<host path> /Users/<user>/...
  ```

  Read guest-written files with `darling shell cat`. Before blaming a framework for "not seeing" a file, check where it was written from.
- **Root:** `darling shell sudo <cmd>`.
- **Daemons:** `darling shell launchctl ...`. Some daemons, trustd for example, take about 20 s to come back after `launchctl stop`.
- **Preferences** written by tests, via `defaults` or CFPreferences, stay in the prefix. Remove them afterwards with `defaults delete`.

## 5. GUI tests
```
scripts/xvfb.sh             # Xvfb :99 (1920x1080x24, RANDR) + xfwm4
timeout -s KILL 120 darling shell env DISPLAY=:99 /Volumes/SystemRoot/.../t </dev/null > out.txt 2>&1
```
- Use display `:99` only. xfwm4 is needed because some window behaviour (focus, stacking, maximise) needs a real window manager.
- Prefer tests that check state through the API, such as frames, key window or pixel readback through the toolkit, over screenshots.

### Wayland
```
eval "export $(scripts/wayland.sh -s 2)"   # headless sway; prints DARLING_APPKIT_BACKEND, WAYLAND_DISPLAY, XDG_RUNTIME_DIR
timeout -s KILL 120 darling shell env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY=$WAYLAND_DISPLAY \
        /Volumes/SystemRoot/.../t </dev/null > out.txt 2>&1
scripts/wayland.sh -s 1.5                 # change the output scale of the running compositor
scripts/wayland.sh stop
```
- **Headless sway** (`WLR_BACKENDS=headless`, pixman renderer) runs in a private runtime directory, so it never touches a desktop session. Its config has no borders and floats every window, so window frames are exactly what the client asked for. It supports xdg-shell, xdg-decoration, xdg-output, fractional-scale, viewporter, pointer-constraints and relative-pointer.
  - `weston --backend=headless` also works for window, clipboard and drag tests, but has no fractional-scale.
  - A nested compositor on Xvfb (`WLR_BACKENDS=x11`) only on a display of its own, such as `:98`, never on the shared `:99`.
- **Backend choice:** AppKit takes `DARLING_APPKIT_BACKEND` (`wayland` or `x11`), then the `DisplayBackend` preference, then uses Wayland whenever `WAYLAND_DISPLAY` is set. If the compositor can't be reached it falls back to X11 silently. So a test must check which backend it actually got (for example the display class) and print SKIP, not PASS, when it is not the one under test.
- **`WAYLAND_DISPLAY` must be the absolute host path** of the socket, not a `/Volumes/SystemRoot/...` path: the host's native libwayland opens it outside the container.
- **The container keeps the environment it started with.** The launcher passes `DISPLAY`, `WAYLAND_DISPLAY`, `XAUTHORITY` and `XDG_RUNTIME_DIR` through to the container's daemons, but only when the container starts. Run `darling shutdown` before switching between X11 and Wayland tests or to a new compositor socket; otherwise daemons keep talking to the old one.
- **Scale:** with an output scale `s`, `NSScreen` and `NSWindow` report the integral `ceil(s)` as `backingScaleFactor`. Content is drawn at that scale and shown at the logical size through wp_viewporter. Test at 1, 2 and a fractional scale such as 1.5.
- **Input:** headless sway has no real devices, so inject virtual ones with `wtype` (virtual keyboard) and `wlrctl` (virtual pointer), both in Debian:
  ```
  export WAYLAND_DISPLAY=... XDG_RUNTIME_DIR=...    # as printed by wayland.sh
  wtype -s 200 'abc é ß' -k Return    # text, then a named key; -M ctrl / -m ctrl hold or release a modifier
  wlrctl pointer move 100 50; wlrctl pointer click left
  ```
  - Always pass **`-s 200`** (a pause first): the client receives the new virtual keyboard's keymap just before the first key, and without the pause that key is lost.
  - Keys go to the focused window. Start typing only after the test window has appeared; with the floating config the newest window has focus.
  - Injected input also provides the input serial that clipboard, drag-and-drop and pointer-lock requests need, so those tests can run instead of SKIP.
  - Pair every injected event with a check through the API (`characters`, `keyCode`, modifier flags, pasteboard contents), printed as PASS/FAIL.
- **After any change to shared AppKit or CoreGraphics code, rerun the X11 GUI tests on Xvfb too.** The two backends share most of the window code.

### Audio
```
python3 -I scripts/audio-ramp.py gen ramp.wav --seconds 4     # 440 Hz tone, level rising linearly from 0.1 to 0.9
scripts/audio-capture.sh cap.raw timeout -s KILL 60 darling shell afplay /Volumes/SystemRoot$PWD/ramp.wav </dev/null
python3 -I scripts/audio-ramp.py analyze cap.raw --seconds 4
scripts/audio-capture.sh ref.raw pacat ramp.wav                # the same tone played natively, as the reference
python3 -I scripts/audio-ramp.py analyze ref.raw --seconds 4
```
- **What the scripts do:**
  - `audio-capture.sh` loads Darling's null-sink fixture (`tests/coreaudio/fixture.sh`) and makes it the default sink. It records the sink's monitor while the command runs, then restores the old default sink. The launcher does not pass `PULSE_SINK` into the guest, so the default sink is how a guest program's output gets routed. Other host programs' audio also goes to the null sink while the capture runs.
  - Because the tone's level rises linearly, each level corresponds to one point of the tone. `analyze` uses this to report the start lost, the end lost, and each gap: either a stall (silence inserted, nothing lost) or lost data, including jumps with no silence. It estimates the playback gain itself, and its resolution is about ±10 ms. A test program can make the same tone itself. What matters is a linear rise of the level, not the file.
- **Always compare with the native `pacat` reference on the same sink.** The monitor misrepresents the edges of a stream, and the cause is the monitor, not the player:
  - On a null sink, the start of a new stream is missing from the capture. Native `pacat` loses about 75 ms at 186 ms latency, and over a second at its default latency. Only lost start beyond the reference is Darling's.
  - On a hardware (ALSA) sink, data dropped at stop never shows as a lost end, because the sink rendered ahead and the monitor already got it. Measure the end on the null sink.
- **Ending the player:** `timeout -s KILL` ends the launcher, but the guest program can keep playing into the next capture. Run `darling shutdown` and `scripts/leftovers.sh -k` before the next capture.

## 6. Regression set
After the targeted tests pass, run your regression set if you keep one (Darling's own `ctest` in the build dir, plus any guest programs you collect). Compare it with the recorded baseline, not with "all green": some cases have known non-zero exit codes. Report what changed against the baseline.

## 7. Report and clean up
- Report, for each test: the command, the result before, the result after, and the regression comparison.
- If you changed host settings (device permissions and so on), say what you changed.
- Afterwards, if the change is not meant to stay installed, revert it in the checkout and reinstall the affected targets, so the next person tests a clean tree. Keep a list of patches applied to the shared checkout, and revert them newest first.
- Remove your scratch files. Don't delete other people's `/tmp` data or screen sockets.
