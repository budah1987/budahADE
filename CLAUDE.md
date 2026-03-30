## Session Continuity
At the start of each session, check your auto-memory for prior context.
Before ending a session, save a brief summary of work done to your auto-memory.

## Branch & Build Hygiene

### Before starting work
- **Check out the correct branch** before dispatching subagents. Confirm with `git branch --show-current`. Subagents commit to whatever branch is checked out.
- **Never work on multiple branches for the same feature.** One branch per feature, start to finish.

### XcodeGen (project generation)
- The project uses **XcodeGen**. `project.yml` is the source of truth — `BudahADE.xcodeproj` is generated.
- **Never edit `project.pbxproj` manually.** Instead, edit `project.yml` and run `xcodegen generate`.
- After creating new `.swift` files, run `xcodegen generate` to regenerate the project. Files are auto-discovered from the directory structure.
- After any build, run `xcodebuild build -scheme BudahADE -quiet 2>&1 | tail -5` to confirm.
- The `.xcodeproj` is gitignored — only `project.yml` is tracked.

### Git safety
- **Never commit large binaries.** `GhosttyKit.xcframework/` and `*.profraw` are in `.gitignore`.
- GhosttyKit is a **symlink** to `~/.superset/worktrees/`. If it goes missing, restore with `git checkout main -- GhosttyKit.xcframework`.
- Before pushing, check for large files: `git diff --stat HEAD~1 | grep -E "\d+ MB"`.
- Use `git add <specific files>` not `git add -A` to avoid accidentally staging binaries or secrets.
