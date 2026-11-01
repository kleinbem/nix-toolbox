#!/usr/bin/env bash
# Tests for bin/nix-check-workarounds against a scratch git repo.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=bin/bash-test-lib.sh
source "$here/bin/bash-test-lib.sh"
tool="$here/bin/nix-check-workarounds"

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base

cat >"$repo/linked.nix" <<'NIX'
{
  # Workaround for a crash on aarch64, drop once this is released:
  # https://github.com/NixOS/nixpkgs/pull/1
  doCheck = false;
}
NIX
cat >"$repo/unlinked.nix" <<'NIX'
{
  # Ordinary comment, nothing to see.
  x = 1;

  # Workaround: the test suite hangs in the sandbox.
  doCheck = false;
  y = 2; # remove once upstream ships 1.2
}
NIX
cat >"$repo/script.sh" <<'SH'
#!/usr/bin/env bash
# until upstream fixes it, see https://example.org/bug/7
true
SH
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m files

echo "== audit of every tracked file"
out=$("$tool" "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "fails when a workaround has no link"
assert_eq "unlinked.nix:5: workaround comment without a link" "$(grep -F 'unlinked.nix:5:' <<<"$out")" "block comment without a link is reported with its first line"
assert_eq "unlinked.nix:7: workaround comment without a link" "$(grep -F 'unlinked.nix:7:' <<<"$out")" "trailing comment without a link is reported"
assert_empty "$(grep -F 'linked.nix:' <<<"$out" | grep -v unlinked || true)" "a linked block passes"
assert_empty "$(grep -F 'script.sh' <<<"$out" || true)" "any http link counts, shebang ignored"
assert_eq "4 workaround comments, 2 without a link" "$(tail -1 <<<"$out")" "summary counts all and the missing ones"

echo "== --base: only changed files"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m empty
out=$("$tool" --base HEAD "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "no changed files, nothing to fail"
printf '# fixed upstream in 2.0, a PR will follow\n' >"$repo/new.nix"
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m new
out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "a new unlinked workaround fails the PR check"
assert_eq "new.nix:1: workaround comment without a link" "$(head -1 <<<"$out")" "only the changed file is reported"

echo "== references and the no-link marker"
cat >"$repo/refs.nix" <<'NIX'
{
  # Drop once NixOS/nixpkgs#573479 reaches nixos-unstable.
  a = 1;
  # That was a workaround for the old image. no-link: only a mention.
  b = 2;
  # Workaround for upstream issue #6175.
  c = 3;
}
NIX
git -C "$repo" add -A
out=$("$tool" "$repo" -- refs.nix 2>&1) && rc=0 || rc=$?
assert_eq "refs.nix:6: workaround comment without a link" "$(head -1 <<<"$out")" "owner/repo#N counts, no-link skips, a bare #N doesn't count"
assert_eq "3 workaround comments, 1 without a link" "$(tail -1 <<<"$out")" "summary for references"

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
    echo "== --states (gh)"
    printf '# Workaround, drop once kleinbem/nix-toolbox#1 is in.\n' >"$repo/merged.nix"
    git -C "$repo" add -A
    out=$("$tool" --states "$repo" -- merged.nix 2>&1) && rc=0 || rc=$?
    assert_eq "merged.nix:1: https://github.com/kleinbem/nix-toolbox/issues/1 is MERGED; drop the workaround once the fix is in what we use" \
        "$(head -1 <<<"$out")" "a merged PR behind owner/repo#N is reported"
fi

echo "== pathspec"
out=$("$tool" "$repo" -- '*.sh' 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "pathspec limits the files"

test_summary
