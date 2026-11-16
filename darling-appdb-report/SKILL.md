---
name: darling-appdb-report
description: Test a macOS application in Darling and contribute a compatibility report to the Darling AppDB (darlinghq/darling-appdb-database) - install the app in the guest, run it in an X11 or Wayland session with a white background, exercise its main functions, take useful screenshots within the size limits, rate it, write the JSON entry and open the pull request. Use when asked to test an app for the AppDB, add an app or version to it, or submit a compatibility report.
---

# Contributing an AppDB compatibility report

The AppDB (appdb.darlinghq.org) lists how well macOS applications work in Darling. Its data lives in **darlinghq/darling-appdb-database** as JSON files plus screenshots. A report is added by a pull request. A workflow validates each PR and merges trusted ones automatically; the rules are in that repo's `.github/scripts/validate_pr.py`, which is the authority if this file disagrees.

This skill builds on **darling-guest-testing** (running programs in the guest, Xvfb, headless sway, input injection). Read that skill's ground rules first: `</dev/null`, `timeout -s KILL`, no piping `darling shell` output, no `rm` in the guest.

Host tools needed: ImageMagick, `pngquant`, `xdotool` and `xwd` for X11, `grim` for Wayland, plus `wtype` and `wlrctl` to type and click on Wayland. If one is missing, ask the user to install it; don't work around it.

## 1. Pick the app and version
- Note the exact version and its **official download URL** (https, from the vendor; no mirrors, URL shorteners or raw IPs, which block auto-merge).
- Check the database first. An existing software or version entry is reused, never edited (see section 7).
- Untrusted download: give each download its own new directory in the scratchpad, keep scripts elsewhere, and never run anything from it on the host.
- Check the binary's architectures with `llvm-objdump --macho --universal-headers` (it prints nothing for a thin, single-architecture binary; use `llvm-objdump --macho --private-headers <binary> | head` and read `cputype`, or `file`). On an x86_64 Darling, an arm64-only build cannot run; say so in the report rather than testing it.

## 2. Install it in the guest
Host files are visible in the guest under `/Volumes/SystemRoot`.
- **DMG:** mount on the host with `darling-dmg app.dmg <mnt> &` (unmount with `fusermount -u <mnt>`), then `darling shell cp -R "/Volumes/SystemRoot<mnt>/App.app" /Applications/`. Alternatively try `darling shell hdiutil attach /Volumes/SystemRoot<path>/app.dmg`, which also tests Darling's own DMG support.
- **ZIP:** unpack it with Darling's `ditto`, as a user on macOS would: `darling shell ditto -x -k "/Volumes/SystemRoot<path>/app.zip" /Applications`. It keeps the executable bit. Afterwards, check that no `__MACOSX` folder was left in `/Applications`. On a Darling build older than the reimplemented `ditto` (where `ditto -x -k` fails with "Bad argument #1"), use the guest's unzip instead: `darling shell unzip -q -o -d /Applications "/Volumes/SystemRoot<path>/app.zip" -x '__MACOSX/*'`. Use `</dev/null` and `timeout -s KILL` as always.
- **PKG:** `darling shell sudo installer -pkg "/Volumes/SystemRoot<path>/app.pkg" -target /`. A failing installer is a finding for the report, not a reason to unpack the payload by hand without saying so.
- Install the way a user would. Any manual step needed (a quarantine attribute, a missing directory) is a workaround, and it lowers the rating (section 5).

## 3. Start a display session with a white background
Use the darling-guest-testing scripts. Both now give a **white** background: the root window on X11 (`xsetroot -solid white`) and the output background in sway. A white background keeps transparent window corners, shadows and sheets from showing up black, and lets screenshots match the AppDB pages.
```
<guest-testing>/scripts/xvfb.sh                          # X11: Xvfb :99 + xfwm4
eval "export $(<guest-testing>/scripts/wayland.sh)"      # Wayland: headless sway
```
- Test the backend you report on. X11 is Darling's default; Wayland is selected by `DARLING_APPKIT_BACKEND=wayland` plus `WAYLAND_DISPLAY` (see the Wayland section of darling-guest-testing). Run `darling shutdown` before switching between them.
- For a 32-bit (i386) app, `vm.mmap_min_addr` must be 4096 or lower (see section 5). Darling users usually set it permanently (for example `vm.mmap_min_addr = 4096` in a file under `/etc/sysctl.d/`); if your host doesn't have it set, set it before testing.
- Run the app's binary directly, so its output is captured:
  ```
  timeout -s KILL 600 darling shell env DISPLAY=:99 "/Applications/App.app/Contents/MacOS/App" </dev/null > app.log 2>&1 &
  ```
  `open -a` also works, but loses the log. Give the app time to start; a first launch can take longer while caches are built.
- A splash screen, intro video or loading screen lasts only a few seconds. To report what happens there, start a capture loop in the same command as the launch, for example `for i in $(seq 1 30); do import -window root -resize 480x270 v$(printf %02d $i).jpg; sleep 0.7; done`, then look at a `montage` contact sheet of the frames. Also check whether the bundle contains the media file at all (`find <App>.app -iname '*.mov' -o -iname '*.mp4'`) and say so.
- To stop leftovers, `pkill -f` with a bracketed pattern (`pkill -f '[A]ngry Birds.app/Contents/MacOS'`) and run it as its own command; a pattern that also appears in the command line of the shell running it kills that shell.

## 4. Test what it is for
A report is only useful if it says what works. Test like a user, in this order:
1. Launch: does the main window appear, with readable text and correct layout?
2. The app's core task, end to end. For example: an editor opens, edits, saves and reopens a file; a calculator computes; a game reaches gameplay and responds to input; a utility does its one job.
3. The menu bar and common shortcuts (Cmd+O, Cmd+S, Cmd+Q), preferences, resizing, and opening and saving through the file dialogs.
4. Anything the app depends on: networking, audio, OpenGL/Metal rendering, printing, clipboard, drag and drop.
5. Quitting cleanly, and a second launch. On X11 the Command key is the Super key: `xdotool key super+q` is Cmd+Q (`alt+q` does nothing). Confirm the process is gone afterwards.

Input:
- On X11, drive it with `xdotool` (`key`, `type`, `mousemove`, `click`).
- On Wayland, use `wtype -s 200 ...` and `wlrctl pointer ...`.
- Check each result on screen (screenshot) or in files the app wrote.

Note crashes, hangs, missing or garbled drawing, and error dialogs, with the log lines that go with them (`app.log`, and crash output in the guest). If a failure has a Darling GitHub issue, note its number; if not, consider filing one. Write findings down as you go.

## 5. Rate it
Use the status that matches what you saw:

| Status | Meaning |
|---|---|
| platinum | Installs and runs out of the box; everything tested works. |
| gold | Everything that matters works, but only after a workaround, or with a small flaw that doesn't get in the way of using it (for example an intro video that doesn't play). Describe it in the report. |
| silver | Usable for its main purpose, with minor problems in secondary features or drawing. |
| bronze | Starts and partly works, but major features fail or it is unstable. |
| garbage | Doesn't install, doesn't start, or is unusable. |

The database only defines the five names; these meanings follow the usual AppDB convention. Rate what you actually tested; when in doubt, take the lower rating and explain why.

Host settings that Darling expects for a whole class of apps are not workarounds and don't lower the rating. The main one: **32-bit (i386) apps need `vm.mmap_min_addr` at 4096 or lower** (`sudo sysctl vm.mmap_min_addr=4096`; most distributions default to 65536). Their binaries are usually linked to load at 0x1000, and without the setting Darling fails to map them ("Cannot mmap segment __TEXT at 0x1000: Operation not permitted"). Mention the setting in the report so readers know to set it, but rate as if it were set.

## 6. Screenshots that help
At most **5** per report, each **at most 150 KB**, PNG or JPEG. `scripts/shot.sh` captures and shrinks them:
```
scripts/shot.sh -w "Window Title" shot1.png     # one window (X11 via DISPLAY, Wayland via WAYLAND_DISPLAY)
scripts/shot.sh shot2.jpg                       # whole screen; JPEG for photo-like or game content
```
- **Show the app doing its job**, not a splash screen, an empty window or a loading bar. One screenshot of the main window with real content is worth more than several of dialogs.
- **One idea per screenshot:** the main window in use, a key feature working, and, if something is broken, the clearest picture of the breakage (the garbled view or the error dialog).
- **Crop to the window** (`-w`), with the white background around it. Make the window a sensible size first; a 600x400 window reads better scaled down than a full 1920x1080 screen.
- **PNG for UI** (sharp text; `pngquant` keeps it small), **JPEG for games, video and photos**. `new_entry.py` keeps the extension (`screenshot-0.jpg`); the validator accepts only `.png` and `.jpg`, not `.jpeg`. A full-screen capture converted with `convert shot.png -resize 1280x720 -strip -quality 85 out.jpg` is usually under 150 KB. If text becomes unreadable at 150 KB, crop tighter instead of shrinking further.
- **No personal data:** no real names, email addresses, usernames in paths, host names, tokens or licence keys. Use a neutral guest user and sample documents.
- **Wait for drawing to finish.** `-w` waits up to 10 s for the window to appear, but not for its contents; a capture right after a window opens can show it half drawn. Wait until the app is idle (a few seconds, longer for games and first launches) before shooting.
- Check each file by looking at it before submitting.

## 7. Write the entry
Fork darlinghq/darling-appdb-database and clone your fork (for a local trial without a fork, a plain clone and a local branch work; use `origin/master` as the base below). Then:
```
python3 -I scripts/new_entry.py <checkout> "<Name>" <version> <status> description.txt \
    --screenshot shot1.png --screenshot shot2.png \
    [--new-software '{"links":{"product":"https://..."},"cpu":["x86-64"],"free":true,"categories":["productivity"]}'] \
    [--new-version '{"download":"https://...","issues":[1234]}']
```
The layout, which the script produces:
- `data/software/<N>/<Na>/<Dir>/index.json`: the software. `name` is the display name; `<Dir>` is that name with every character other than letters, digits, `.`, `_` and `-` removed (`SkyFighters 1945` is stored under `SkyFighters1945`).
  - `cpu` is any of `x86-64`, `i386`, `arm64`. `free` is true or false.
  - `categories` are ids that exist in `data/categories/` (for example games, productivity, developer-tools).
  - `links` maps labels such as `product` to https URLs.
  - The shard directories are the directory name's first character and first two characters, case-sensitive; `_` replaces the second for one-character names.
- `.../versions/<version>/index.json`: `version` must equal the directory name. `download` is the official https URL. `issues` lists related Darling GitHub issue numbers.
- `.../versions/<version>/reports/<8 hex digits>.json`:
  - `status`, `description` (at most 5000 characters) and `screenshots` (file names).
  - The screenshots go in `reports/<same id>/screenshot-0.png`, `screenshot-1.png`, and so on. The script picks a random id.

Rules that matter:
- **Name:** the product's own spelling as people see it, with its spaces and capitals: `The Unarchiver`, `SkyFighters 1945`, `Angry Birds`, `TextEdit`. Take it from the app's menu bar, About window or the vendor's site, not from the bundle's file name. Leave out version numbers and words such as "for Mac" or "Free", unless the product's name really includes them. `new_entry.py` derives the directory from it; single spaces only, at most 100 characters. A name whose directory differs from an existing one only by case is rejected. Pass the name quoted on the command line.
- **New files only:** a PR may only add files. Changing an existing file is allowed but always needs a maintainer.
- **One app per PR:** keep each PR to one software. Each report gets its own id.

The description should cover:
- what you did with the app and how it went: what works, what doesn't, and how much the flaws get in the way;
- how to install it, and anything a reader must set or do first (such as `vm.mmap_min_addr` for 32-bit apps);
- the host distribution and X11 or Wayland, in a short closing line.

**Write it for people, not as a test log.** The readers are Darling users deciding whether an app is worth trying, so write like a person telling a friend how it went:
- Use plain, friendly sentences in the first person ("I played through the first episode, and the music and effects played throughout"). Start with the overall impression, then the details that matter.
- Say what the app is like to use, not what you measured. "Sound works" beats "78 of 78 100 ms windows were audible"; "it quits with Cmd+Q and starts again fine" beats a list of exit codes.
- Leave out cold facts that mean nothing to a user: commit hashes, PR and branch names, build numbers, test-tool names, capture durations, log lines and Darling internals (frameworks, function names, error codes). The Darling version can be a rough date or release.
- Describe a flaw by what the user sees and whether it matters ("the logo is drawn into a corner of the window for a few seconds; after that the game looks right").
- State only what you saw. Don't guess at causes, and check claims before making them (for example, look whether the app even ships the video you think is missing).
- Keep it short: a few short paragraphs.

**Markdown.** The AppDB site renders the report description as GitHub-flavoured Markdown, so you can use it to make the report easier to read:
- `**bold**` for the one thing a reader must not miss, short bulleted lists for steps or a few separate problems, and `` `code` `` for commands and settings (`` `sudo sysctl vm.mmap_min_addr=4096` ``).
- Links to Darling issues (`[#1234](https://github.com/darlinghq/darling/issues/1234)`) or the vendor's page.
- A single newline already becomes a line break, so don't hard-wrap sentences; separate paragraphs with a blank line.
- Keep it light: no headings, tables or images (screenshots go in their own field). Raw HTML and scripts are stripped. In the JSON file the description is one string, so newlines are written as `\n`; `new_entry.py` takes care of that when it reads the text file.

The PR body follows the same style: two or three friendly sentences, not a list of facts.

## 8. Validate and open the PR
Run the repository's own validator against your commit before pushing (`facts` are only used for the auto-merge decision):
```
git -C <checkout> fetch upstream && git -C <checkout> commit -m "Add <Name> <version> (<status> report)"
python3 -I <checkout>/.github/scripts/validate_pr.py --repo <checkout> --base upstream/master --head HEAD   # origin/master in a plain clone \
    --merged-prs 1 --open-prs 1 --author-created-at 2020-01-01T00:00:00Z
```
- Fix every `errors` entry.
- A `reasons` entry is not a failure; it means a maintainer merges the PR by hand. That happens, for example, for a new software or version from an author without an earlier merged PR, or for an http download link.

Push to a branch of your fork and open the PR against `master`:
```
gh pr create -R darlinghq/darling-appdb-database --base master --head <you>:<branch> \
    --title "Add <Name> <version> (<status> report)" --body "<two or three friendly sentences: how the app runs and what to watch out for>"
```
Before you push:
- **Ask the user first.** Opening a PR publishes the report.
- **Screenshots must be clean:** check every screenshot again for personal data.

After you push, the workflow posts a comment: "Validated" (merged automatically), "Needs a maintainer", or a list of errors to fix.

## 9. Clean up
- Quit the app.
- `darling shutdown`.
- Stop the sessions you started: `wayland.sh stop`. Leave the shared Xvfb running.
- Unmount any DMG.
- Remove the scratch downloads.
- An app installed in the guest prefix can stay, unless the user wants a clean prefix.
