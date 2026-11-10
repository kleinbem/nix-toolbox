#!/usr/bin/env bash
# Tests for bin/nix-check-nixpkgs-pr against a scratch git repo.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=bin/bash-test-lib.sh
source "$here/bin/bash-test-lib.sh"
tool="$here/bin/nix-check-nixpkgs-pr"

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base

echo "== testers.runCommand is flagged as failure"
mkdir -p "$repo/pkgs/by-name/fo/foo"
cat >"$repo/pkgs/by-name/fo/foo/package.nix" <<'NIX'
{ runCommand, testers }:
{
  passthru.tests.network = testers.runCommand "bad-test" { } "touch $out";
}
NIX
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "add foo"

out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "fails when testers.runCommand is used"
assert_eq 1 "$(grep -c 'uses testers.runCommand' <<<"$out" || true)" "reports testers.runCommand failure"

echo "== handwritten completion is noted"
cat >"$repo/pkgs/by-name/fo/foo/package.nix" <<'NIX'
{ runCommand }:
{
  postInstall = ''
    cat <<EOF > $out/share/bash-completion/completions/foo
    complete -F _foo foo
    EOF
  '';
}
NIX
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "add inline completion"

out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$(grep -c 'inline shell completion creation' <<<"$out" || true)" "notes inline completion"

echo "== PR body checks"
body_bad="$repo/bad-body.md"
cat >"$body_bad" <<'MD'
Custom description without things done.
MD
out=$("$tool" --base HEAD~1 --pr-body "$body_bad" "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "fails when PR body is missing template headings"

body_human="$repo/human.md"
cat >"$body_human" <<'MD'
## Things done
* [X] Follows the [automation/AI policy]
MD
out=$("$tool" --base HEAD~1 --pr-body "$body_human" "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "human PR passes policy checkbox without disclosure"
assert_eq 1 "$(grep -c 'no AI trailer detected in branch' <<<"$out" || true)" "reports no AI trailer"

# Add commit with Assisted-by trailer
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "assisted commit

Assisted-by: Antigravity (gemini-3.8-flash)"

body_ai_nodisclose="$repo/nodisclose.md"
cat >"$body_ai_nodisclose" <<'MD'
## Things done
- [x] Follows the [automation/AI policy]
MD
out=$("$tool" --base HEAD~1 --pr-body "$body_ai_nodisclose" "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "fails when AI-assisted commit has no PR disclosure"

body_good="$repo/good.md"
cat >"$body_good" <<'MD'
## Things done
- [x] Follows the [automation/AI policy]
Assisted by Antigravity (gemini-3.8-flash).
MD
out=$("$tool" --base HEAD~1 --pr-body "$body_good" "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$(grep -c 'checks automation/AI policy and contains disclosure phrase' <<<"$out" || true)" "passes good PR body"

test_summary
