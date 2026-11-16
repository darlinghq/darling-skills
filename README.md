# Darling skills for AI coding agents

Instructions and helper scripts that teach an AI coding agent how to work on [Darling](https://github.com/darlinghq/darling): build and test a change inside the guest, debug a program, check an app's compatibility, and contribute an AppDB report.

| Skill | What it covers |
|---|---|
| `darling-guest-testing` | Rebuilding and installing only what changed, cross-compiling guest test programs, running them with `darling shell`, GUI tests on Xvfb (X11) or headless sway (Wayland), input injection, measuring audio output, cleaning up leftovers |
| `darling-debugging` | lldb inside the guest: installing it, batch debugging of x86_64 and i386 programs, diagnosing debugger failures |
| `darling-app-compat-scan` | Listing the frameworks, classes and symbols an application uses that Darling lacks |
| `darling-appdb-report` | Testing an app and submitting a compatibility report to [darling-appdb-database](https://github.com/darlinghq/darling-appdb-database) |

The other skills build on `darling-guest-testing`, so install all of them together.

Each skill is a directory with a `SKILL.md` and, where needed, a `scripts/` directory:
- **`SKILL.md`:** a short YAML header (`name`, `description`) followed by Markdown instructions. The agent reads the description to decide when a skill applies, and the body when it uses it.
- **Scripts:** run from inside a Darling checkout. They find the checkout, build directory and installed Darling on their own; `darling-guest-testing/SKILL.md` lists the environment variables that override this.

## Requirements
- Linux with a Darling source checkout, a build directory and an installed Darling. The skills test changes in a real Darling, so they need a machine that can run it.
- For GUI work:
  - X11: Xvfb, xfwm4, `xdotool` and `xwd`;
  - Wayland: sway, `grim`, `wtype` and `wlrctl`;
  - for screenshots: ImageMagick and `pngquant`.

  Each skill says what it needs.
- An agent that can run shell commands on that machine.

## Claude Code
Claude Code loads skills from `~/.claude/skills/` (all your projects) and from `.claude/skills/` in a project.

Install for yourself:
```
git clone https://github.com/darlinghq/darling-skills.git ~/darling-skills
mkdir -p ~/.claude/skills
for s in ~/darling-skills/darling-*/; do ln -sfn "$s" ~/.claude/skills/"$(basename "$s")"; done
```
The symlinks keep the skills current: a `git pull` in `~/darling-skills` updates them. Use copies instead of symlinks if you want to edit them locally without affecting the clone.

To use them only in your Darling checkout, link them into `<darling>/.claude/skills/` instead. Don't commit those links to the Darling repository.

Start a new Claude Code session afterwards and check with `/skills`, or ask "which skills do you have?". Claude uses a skill on its own when a task matches its description. You can also ask for one by name, for example "use the darling-debugging skill to get a backtrace of this crash".

The skills use the scratchpad, `sudo -n` for installs, and `ssh` only where you set up a Mac for observation. Allow or deny those in Claude Code's permission settings as you prefer.

## Google Antigravity
Antigravity discovers skills globally from `~/.gemini/config/skills/` and per-workspace from `.agents/skills/`.

Install for yourself (all workspaces):
```
mkdir -p ~/.gemini/config/skills
for s in ~/darling-skills/darling-*/; do ln -sfn "$s" ~/.gemini/config/skills/"$(basename "$s")"; done
```

To use them only in your Darling checkout:
```
mkdir -p <darling>/.agents/skills
for s in ~/darling-skills/darling-*/; do ln -sfn "$s" <darling>/.agents/skills/"$(basename "$s")"; done
```

Antigravity uses progressive disclosure: skill descriptions are indexed into context at startup, and the full `SKILL.md` is loaded on demand when a task matches.

## Codex
Codex discovers skills globally from `~/.codex/skills/` (and `~/.agents/skills/`) and project-locally from `.codex/skills/` or `.agents/skills/`.

Install for yourself:
```
mkdir -p ~/.codex/skills
for s in ~/darling-skills/darling-*/; do ln -sfn "$s" ~/.codex/skills/"$(basename "$s")"; done
```

To use them only in your Darling checkout:
```
mkdir -p <darling>/.codex/skills
for s in ~/darling-skills/darling-*/; do ln -sfn "$s" <darling>/.codex/skills/"$(basename "$s")"; done
```

## OpenCode
OpenCode natively supports `SKILL.md` skills, discovering them globally from `~/.config/opencode/skills/` and project-locally from `.opencode/skills/` (and `.agents/skills/`).

Install for yourself:
```
mkdir -p ~/.config/opencode/skills
for s in ~/darling-skills/darling-*/; do ln -sfn "$s" ~/.config/opencode/skills/"$(basename "$s")"; done
```

To use them only in your Darling checkout:
```
mkdir -p <darling>/.opencode/skills
for s in ~/darling-skills/darling-*/; do ln -sfn "$s" <darling>/.opencode/skills/"$(basename "$s")"; done
```

## Claude Agent SDK
Agents built with the Claude Agent SDK load skills from the same directories when filesystem settings are enabled: `.claude/skills/` in the working directory, or `~/.claude/skills/` for user settings. Install them as for Claude Code and enable the matching setting sources in your agent's options. See the SDK's documentation on skills for the exact option names in your SDK version.

## Claude apps (claude.ai, desktop)
The Claude apps can upload custom skills as zip files (one skill per zip, with `SKILL.md` at the top of the skill directory) where skills are enabled for your plan:
```
cd ~/darling-skills && zip -r darling-debugging.zip darling-debugging
```
These skills drive a local Darling installation, though, and skills in the apps run in Claude's own sandbox, not on your machine. There they're useful as reference: for example, to ask how to set up an AppDB report or what an lldb error means. For actual testing, use Claude Code on the machine that runs Darling.

## Other agents and harnesses
`SKILL.md` is plain Markdown with a small header, so any agent that can read files and run commands can use these instructions:
- **Agents that support skills in the same format:** several coding agents read `SKILL.md` directories from a skills folder of their own. Check your tool's documentation for its skills directory, and link or copy the skill directories there as shown above.
- **Agents with a project instructions file:** for example `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md` or Cursor rules. Add a short pointer instead of copying the skills in:
  ```
  ## Darling skills
  Before testing or debugging Darling changes, read the matching skill in ~/darling-skills/:
  - darling-guest-testing/SKILL.md: building, installing and running tests in the guest
  - darling-debugging/SKILL.md: lldb inside the guest
  - darling-app-compat-scan/SKILL.md: which APIs an app needs that Darling lacks
  - darling-appdb-report/SKILL.md: AppDB compatibility reports
  Run their scripts from the skill's scripts/ directory, inside the Darling checkout.
  ```
  Put this in your personal instructions file, not in the Darling repository's `AGENTS.md`.
- **Chat assistants without tool access:** paste the relevant `SKILL.md` into the conversation as context. The assistant can then tell you the steps, but you run them yourself.

Whatever the harness, the Darling repository's `AGENTS.md` still applies to all code an agent writes for Darling: clean-room rules, layering, quirks and provenance. The skills don't replace it.

## Contributing
Changes are welcome as pull requests.
- **Paths:** keep skills free of paths specific to one machine; scripts autodetect, and environment variables override.
- **One task per skill:** cross-reference other skills by name rather than repeating them.
- **Description:** keep the `description` line accurate. It decides when an agent picks the skill.
