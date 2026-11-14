---
name: darling-debugging
description: Debug a program running inside Darling with lldb - install the known-working lldb build in the guest, run x86_64 and i386 programs under it in batch mode, read stop reasons and backtraces, diagnose failures of lldb itself (debugserver logs, strace), and recognise 32-bit Objective-C fragile instance-size corruption. Use when a guest program crashes, hangs or misbehaves and a backtrace or live inspection is needed.
---

# Debugging programs inside Darling

This skill builds on **darling-guest-testing**: building test programs (`guest-cc.sh`), Xvfb and Wayland sessions, the ground rules (`</dev/null`, `timeout -s KILL`, no piping `darling shell` output, no `rm` in the guest) and cleanup of leftovers. Read that first. The scripts here are in `scripts/`.

## 1. Install lldb in the guest
```
scripts/install-lldb.sh [<work dir>]
```
It downloads the maintainers' known-working build (https://darling-misc.s3.eu-central-1.amazonaws.com/lldb.tar.bz2), unpacks it on the host and copies it into the guest at `/usr/local/lldb`. It then prints `lldb-360.99.0`.

About this build:
- It's lldb 360.99 (Xcode 9 era), built from LLVM sources.
- **No arm64 support.** Every binary in the archive is x86_64, so lldb itself can't run on an arm64 Darling (an arm64 host), and it can't debug arm64 processes. It debugs x86_64 and i386 processes on an x86_64 Darling. On arm64 there is no known-working lldb yet; don't try to make this one work there.
- It needs a Darling with three fixes from November 2026. Without them:
  - `lldb --version` dies in dyld with a missing `__shared_weak_count::__add_shared` (libc++ legacy exports);
  - i386 programs fail with "Cannot mmap commpage: File exists" (mldr with ASLR disabled);
  - lldb hangs when the program exits (`wait4` on an attached process).
- Don't commit or redistribute the archive.
- Apple's Command Line Tools (`xcode-select --install`) are the fallback only if this build can't work. Newer lldb versions need macOS symbols Darling may lack.

## 2. Run a program under lldb
Write the lldb commands to a host file and run them in batch mode:
```
cat > cmds.lldb <<'X'
b main
run
bt
frame variable
next
continue
X
scripts/lldb-run.sh cmds.lldb out.txt /path/in/guest/program [args...]
```
- The program path is a guest path. Host files are visible under `/Volumes/SystemRoot`.
- Build test programs with debug info: `guest-cc.sh [-a i386] -o prog prog.c -g`. Options for `guest-cc.sh` itself come first; `-g` goes after the sources, with the other clang flags.
- For a GUI program, start Xvfb or sway first, and pass the display variables to the program with `settings set target.env-vars DISPLAY=:99` (or the Wayland variables) at the top of the commands file.
- Interactive use works too (`darling shell /usr/local/lldb/lldb <program>`), but batch runs leave a complete transcript and never block an agent.
- If a command hangs, `lldb-run.sh` kills the session after its timeout (`-t`, default 300 s). Kill leftover Darling processes afterwards.

Known to work on x86_64 and i386:
- breakpoints by name or line;
- `run`, `bt`, `frame variable`, `print`, `next`, `step`, `finish`, `continue`;
- `register read`;
- normal exit ("Process N exited with status = ...").

Crashes stop with the macOS stop reason:
- a null dereference shows `EXC_BAD_ACCESS (code=1, address=0x0)`;
- `abort()` shows `signal SIGABRT`.

Both come with a correct backtrace. Frame 0 of an abort is a syscall stub in libsystem_kernel, and there may be a duplicate `start` frame at the bottom.

Known limitations:
- **i386:** debugging i386 programs needs the host's `vm.mmap_min_addr` at 4096 or less, as any i386 program does (`sudo sysctl vm.mmap_min_addr=4096`). Restore the previous value afterwards.
- **External dSYM lookup:** it prints noise on each run; ignore it. This lldb version has no setting to turn it off.
- **"unable to attach":** an occasional failure on the first run right after killing leftover processes. Retry once.
- **abort exit status:** after `continue` from a SIGABRT, an x86_64 run may report exit status 0 instead of signal 6. The real parent can reap the process first.
- **Stop statuses:** an attached process's stop statuses (`wait4` with `WUNTRACED`) aren't reported. lldb doesn't need them; it uses Mach exceptions.

## 3. When lldb itself misbehaves
- **debugserver's view:** set `LLDB_DEBUGSERVER_LOG_FILE=<guest path>` in lldb's environment. The log shows attach, exception and `waitpid` results.
- **Host side:** `strace -f -p <pid>` on the host process of `debugserver` or of the target shows failing syscalls, for example `wait4(...) = -1 ECHILD`. Find PIDs with `ps` on the host; guest processes are host processes.
- **An external debugserver** separates the two halves:
  1. `darling shell /usr/local/lldb/debugserver 127.0.0.1:12345 <program>`
  2. In lldb: `platform select remote-macosx`, then `process connect connect://127.0.0.1:12345`.
- **Where fixes belong:**
  - `task_for_pid`, tracer bookkeeping: darlingserver;
  - `ptrace` and `wait4` emulation, exception delivery, execve: darling-xnu;
  - process start-up and address layout: mldr in the darling repo;
  - missing symbols at lldb start-up: the library that should export them.

  Fix the general behaviour, never something lldb-specific.

## 4. Crashes in 32-bit Objective-C apps: check the instance sizes
32-bit macOS apps use the legacy (fragile) Objective-C ABI. A subclass's instance size and ivar offsets are fixed when the app is compiled, against Apple's superclass layout. If Darling's superclass is larger, the app's ivars overlap Darling's and its instances are allocated too small. The result is heap corruption that shows up far from its cause:
- garbage `isa` values in `objc_msgSend` or selector registration;
- `release` sent to objects holding text;
- `-[__NSCFString _view]: unrecognized selector` and similar type confusion;
- faults that move from run to run.

To check:
1. Set `OBJC_DEBUG_FRAGILE_SUPERCLASSES=YES` in the program's environment. The runtime warns about subclasses whose ivars overlap their superclass.
2. Read the app's own class layout from its binary: `llvm-objdump --macho --objc-meta-data <app binary>`. It shows instance sizes and ivar offsets.
   - Disassembling and inspecting the app's own non-Apple code is allowed for compatibility troubleshooting.
   - Never inspect Apple binaries, including Apple frameworks bundled inside an app.
3. Compare with Darling's sizes: a small guest program printing `class_getInstanceSize` and `ivar_getOffset` for the superclasses, built with `-a i386`.

A subclass's first ivar offset equals Apple's superclass size. If Darling's superclass is bigger, that is the bug. Darling's AppKit is being changed to keep Apple's legacy-ABI instance sizes, with extra state behind a pointer; each converted class declaration states the size it must keep. Never add ivars past a stated size, and report a class whose size differs from Apple's.

x86_64 and arm64 use the non-fragile ABI, whose runtime slides ivars, so they aren't affected.

## 5. Clean up
- Restore `vm.mmap_min_addr` if you changed it.
- Kill leftover Darling processes (`leftovers.sh` from darling-guest-testing) and delete `/tmp/core.*`.
- `/usr/local/lldb` can stay installed in the prefix.
