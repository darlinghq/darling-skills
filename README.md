# Darling Skills

Agent skills for developing, testing, and diagnosing applications on [Darling](https://github.com/darlinghq/darling) (the macOS translation layer for Linux).

Compatible with **Claude Code**, **Google Antigravity**, **Codex**, and any agent platform that supports standard `SKILL.md` skill definitions.

---

## Included Skills

### 1. `darling-app-compat-scan`
Estimates what a macOS application needs from Darling by combining a static symbol audit with a live run.
- **Static Scan**: Uses `llvm-objdump` and `llvm-nm` to inspect Mach-O binaries in `.app` bundles, `.dmg`, `.pkg`, or `.zip` archives. Follows re-exported dylibs (`LC_REEXPORT_DYLIB`) and checks for missing libraries and unresolved strong/weak symbol imports against an installed Darling runtime.
- **Runtime Triage**: Provides step-by-step guidance for running the app inside the Darling container under headless X11 (`Xvfb :99`) to identify the first fatal failure (missing dylib, missing symbol, or unhandled Objective-C selector).
- **Scripts**:
  - `scripts/scan_app.py`: Scans Mach-O files and generates ranked terminal or JSON reports.

### 2. `darling-guest-testing`
End-to-end workflow for compiling, installing, and testing Darling changes inside the guest container.
- **Fast Incremental Builds**: Avoids full `make install` overhead by rebuilding only modified targets and installing them directly using `cmake -P cmake_install.cmake`.
- **Guest Cross-Compilation**: Compiles Darwin test binaries directly on the host using Clang with source-tree SDK headers and Darling ld64/runtime stubs.
- **CLI & GUI Testing**: Best practices for executing tests with `darling shell`, enforcing timeouts (`timeout -s KILL`), preventing pipeline hangs, and setting up display backends:
  - **X11**: Headless `Xvfb :99` with `xfwm4`.
  - **Wayland**: Headless `sway` with fractional scale support (`wp_viewporter`) and synthetic input injection (`wtype`, `wlrctl`).
- **Clean Container Lifecycle**: Automated shutdown, restart retries, and detection/cleanup of orphan `mldr` and `darlingserver` processes.
- **Scripts**:
  - `scripts/env.sh`: Automatically locates the Darling checkout, build directory, SDK, and launcher.
  - `scripts/rebuild.sh`: Rebuilds and installs targeted targets.
  - `scripts/restart.sh`: Cleanly stops and restarts the Darling container.
  - `scripts/leftovers.sh`: Audits and optionally kills lingering host/guest processes.
  - `scripts/guest-cc.sh`: Cross-compiles test programs (`.c`, `.m`, `.dylib`).
  - `scripts/xvfb.sh`: Launches Xvfb (:99) and xfwm4.
  - `scripts/wayland.sh`: Manages private headless Sway sessions for Wayland tests.

---

## Prerequisites

- **Darling**: An installed Darling root tree (accessible via the `darling` launcher on `PATH` or at `/usr/local/libexec/darling`).
- **Host Tools**:
  - `clang` (with Apple target support)
  - `llvm-objdump`, `llvm-nm`
  - `python3` (for the static scan script)
  - `darling-dmg` (optional, for mounting `.dmg` images via FUSE)
- **GUI Testing (Optional)**:
  - `xvfb`, `xfwm4` (X11)
  - `sway`, `wtype`, `wlrctl` (Wayland)

---

## Installation

### Claude Code

To make these skills available globally in Claude Code:

```bash
mkdir -p ~/.claude/skills
cp -r darling-app-compat-scan darling-guest-testing ~/.claude/skills/
```

Or for a specific project/workspace:

```bash
mkdir -p .claude/skills
cp -r darling-app-compat-scan darling-guest-testing .claude/skills/
```

### Google Antigravity

To make these skills available globally in Antigravity:

```bash
mkdir -p ~/.gemini/config/skills
cp -r darling-app-compat-scan darling-guest-testing ~/.gemini/config/skills/
```

Or for a specific project/workspace:

```bash
mkdir -p .agents/skills
cp -r darling-app-compat-scan darling-guest-testing .agents/skills/
```

### Codex / Cursor

Add the skills to your user or project agent skills folder:

```bash
# Global / user-level:
mkdir -p ~/.agents/skills
cp -r darling-app-compat-scan darling-guest-testing ~/.agents/skills/

# Or project-level:
mkdir -p .cursor/skills
cp -r darling-app-compat-scan darling-guest-testing .cursor/skills/
```

---

## License

Distributed under the same licensing terms as the Darling project (GNU General Public License v3 or later).
