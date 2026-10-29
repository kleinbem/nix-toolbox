# nix-toolbox

Generic Nix flake development-workflow tools — each script runs against
whatever repo/flake you point it at (or `cwd` by default), with no
dependency on any particular fleet's registry or layout.

Put `bin/` on `PATH` to use these directly.

| Script | What it does |
|---|---|
| `nix-check-versions [dir]` | Detect version-pinning drift: the same package pinned to different versions across `.nix` files |
| `nix-audit-deps [repo-path] [old-lock-file]` | Audit transitive dependency version changes via `flake.lock` — flags major version bumps in common C libraries (override the watch list with `WATCH_PACKAGES`) |
| `nix-audit-locks <flake-dir> <repo-dir>...` | Compare a flake's locked input revisions against the actual git HEAD of local sibling repos, report drift |
| `nix-verify-devshells [flake-ref]` | Build every devShell a flake defines (introspected, not hardcoded) for the current system, report pass/fail per shell |
| `nix-check-nixpkgs-pr [--pr number|url] [--base rev] [--log file] [--drvs-against rev] [dir]` | Mechanical checks for a nixpkgs PR branch or remote PR: variants' `meta.position` in their own file, option links in module docs (notes `{option}`), a link on every workaround comment (state via `gh` if present), `deadnix` and `statix` on new files, common review anti-patterns (legacy python format, rev vs tag, unexplained doCheck = false, maintainer emails); optionally groups a build log's warnings and tells which derivations changed since a revision |
| `nix-check-lock [lock-path] [pgrep-pattern]` | Inspect a flock file used to serialize long-running builds — is it held, and by what |
| `bash-test-lib.sh` | Sourced (not executed) — hand-rolled `assert_eq`/`assert_empty`/`test_summary` bash test helpers |

See `CLAUDE.md` for conventions and gotchas before adding a new tool.
