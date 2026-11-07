# nix-toolbox

Generic Nix flake development-workflow tools — each script runs against
whatever repo/flake you point it at (or `cwd` by default), with no
dependency on any particular fleet's registry or layout.

Put `bin/` on `PATH` to use these directly.

| Script | What it does |
|---|---|
| `nix-check-versions [dir]` | Detect version-pinning drift: the same `<name>Version = "…"` pin (e.g. `platformToolsVersion`, `python3Version`) set to different versions across `.nix` files. The value must start with a digit (`"v1.2"` is skipped); plain `version = "…"` assignments aren't checked |
| `nix-audit-deps [repo-path] [old-lock-file]` | Compare watched package versions between the nixpkgs revisions locked in two `flake.lock` files — flags major version bumps in common C libraries (override the watch list with `WATCH_PACKAGES`). Without an old lock it only lists the current versions, no comparison. Reads nixpkgs, not the repo's own overrides |
| `nix-audit-locks <flake-dir> <repo-dir>...` | Compare a flake's locked input revisions against the actual git HEAD of local sibling repos, report drift |
| `nix-verify-devshells [flake-ref]` | Build every devShell a flake defines (introspected, not hardcoded) for the current system, report pass/fail per shell |
| `nix-check-nixpkgs-pr [--pr number\|url] [--base rev] [--log file] [--drvs-against rev] [dir]` | Mechanical checks for a nixpkgs PR branch or remote PR: variants' `meta.position` in their own file, option links in module docs (notes `{option}`), a link on every workaround comment (state via `gh` if present), `deadnix` and `statix` on new files (each only when installed), common review anti-patterns (legacy python format, rev vs tag, unexplained doCheck = false, maintainer emails); optionally groups a build log's warnings and tells which derivations changed since a revision |
| `nix-check-workarounds [--base rev] [--states] [dir] [-- pathspec]` | Every workaround comment links its upstream issue or PR (URL or `owner/repo#123`): fails on ones without, and with `--states` (via `gh`) lists links that are merged or closed, so the workaround can go. `--base` checks only a PR's changed files. Default files: `*.nix`, `*.sh`, `*.bash`, `*.yaml`, `*.yml`, `*.toml`, `*.py`, justfiles, `*.just`; paths after `--` replace them, so to add extensionless scripts list both: `-- '*.nix' '*.sh' bin/` |
| `nix-check-lock [lock-path] [pgrep-pattern]` | Inspect a flock file used to serialize long-running builds — is it held, and which processes match the pattern (possible holders). Needs `flock` (util-linux) |
| `bash-test-lib.sh` | Sourced (not executed) — hand-rolled `assert_eq`/`assert_empty`/`test_summary` bash test helpers |

See `CLAUDE.md` for conventions and gotchas before adding a new tool.
