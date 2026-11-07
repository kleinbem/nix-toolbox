# nix-toolbox

Guidance for AI assistants working in this repository. Tool-specific
filenames (`CLAUDE.md`) are symlinks to this file.

## What this is

Generic Nix flake development-workflow tools, extracted from the kleinbem
fleet's own scripts — each takes a path/flake-ref as an argument (or
defaults to `cwd`), with no dependency on `kleinbem/repos.nix`, a
specific fleet layout, or any hardcoded host/repo names. Same philosophy
as [`jj-toolbox`](https://github.com/kleinbem/jj-toolbox): small, portable,
one script per file.

## Design principles — read before adding a tool

- **Take the target as an argument, don't assume a layout.** The
  originals this repo was extracted from hardcoded things like "the
  sibling directories named `nix-*`" or "the flake at `../nix-devshells`"
  — every tool here replaced that with an explicit argument (a dir, a
  flake ref, a list of repos). Don't reintroduce that coupling.
- **Introspect, don't hardcode a list.** `nix-verify-devshells` used to
  carry two hardcoded arrays of shell names; it now enumerates
  `.#devShells.<system>` via `nix eval --apply builtins.attrNames`. If a
  script needs "every X a flake defines," introspect it — a hardcoded
  list silently goes stale.
- **Portable, no exotic deps.** `nix`, `jq`, `git`, coreutils — that's the
  ceiling. Nothing that assumes a specific devshell is loaded.
- **One script per file**, named `nix-<verb>`, executable, no file
  extension (except `bash-test-lib.sh`, which is sourced, not executed —
  no shebang, no `+x`).

## A real bug we found while porting — regex extraction over a whole line

`nix-check-versions`'s original (`kleinbem/tools/check-version-consistency.sh`)
extracted a package name with `sed -E 's/.*([a-zA-Z]+)Version.*/\1/'` run
against the *whole matched line*. Greedy `.*` backtracking means that
captures only the **last single letter** before "Version" (e.g.
`platformToolsVersion` → `s`), not the identifier — a real, silent bug in
production, not a hypothetical.

Fix: isolate the matched token first with `grep -o` (so parsing starts
right at the identifier, nothing for a leading `.*` to eat into), *then*
extract from that short, unambiguous string. If you're tempted to
"just port" a regex from one of the originals, check it actually does
what its comment claims — don't assume prior art here is correct.

## Adding a new tool

1. `bin/nix-<verb>`, executable, takes its target as an argument (default
   to `.` where a "current directory" reading makes sense).
2. No hardcoded fleet/repo names — if the original you're porting from has
   one, parameterize it.
3. Test against a real flake/repo, not just syntax-check. Several of
   these tools are slow on a cold cache (fresh `nix eval`/`nix build`
   against an unfetched revision) — that's expected, not a bug; use a
   small self-contained scratch flake (no external `inputs`, so it can't
   accidentally pull the flake registry's default nixpkgs over the
   network) to verify logic quickly.
4. Update `README.md`'s table.
