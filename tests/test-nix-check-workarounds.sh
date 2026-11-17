#!/usr/bin/env bash
# Tests for bin/nix-check-workarounds against a scratch git repo.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=bin/bash-test-lib.sh
source "$here/bin/bash-test-lib.sh"
tool="$here/bin/nix-check-workarounds"

repo="$(mktemp -d)"
trap 'rm -rf "$repo" "$repo.bin"' EXIT
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

echo "== --base: only touched comment blocks in changed files"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m empty
out=$("$tool" --base HEAD "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "no changed files, nothing to fail"
printf '# fixed upstream in 2.0, a PR will follow\n' >"$repo/new.nix"
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m new
out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "a new unlinked workaround fails the PR check"
assert_eq "new.nix:1: workaround comment without a link" "$(head -1 <<<"$out")" "only the changed file is reported"

# Modifying an unrelated line in a file that already carries old unlinked
# workarounds (like nixpkgs' all-packages.nix) must not flag the untouched ones. no-link: test prose.
sed -i 's/x = 1;/x = 42;/' "$repo/unlinked.nix"
git -C "$repo" add unlinked.nix
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "touch unrelated line in unlinked.nix"
out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "untouched pre-existing workarounds in a modified file are ignored"
assert_eq "0 workaround comments, 0 without a link" "$(tail -1 <<<"$out")" "zero touched workaround blocks counted"

# Editing inside an existing multi-line workaround block checks the whole block. no-link: test prose.
sed -i 's/hangs in the sandbox./hangs in the sandbox;\n  # still needs investigation./' "$repo/unlinked.nix"
git -C "$repo" add unlinked.nix
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "touch existing workaround block"
out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "editing an unlinked workaround block flags it"
assert_eq "unlinked.nix:5: workaround comment without a link" "$(head -1 <<<"$out")" "reports the touched block's start line"

# diff.noprefix / diff.mnemonicPrefix in user git config must not hide hunks.
git -C "$repo" config diff.noprefix true
git -C "$repo" config diff.mnemonicPrefix true
out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "diff.noprefix and diff.mnemonicPrefix do not hide changed blocks"
git -C "$repo" config --unset diff.noprefix
git -C "$repo" config --unset diff.mnemonicPrefix

# A filename containing a tab (which git quotes in patch headers) is still matched.
tabfile=$'with\ttab.nix'
printf '# Workaround without a link in tab-named file.\n' >"$repo/$tabfile"
git -C "$repo" add -- "$tabfile"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "add tab-named file"
out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "changed workaround in tab-named file is detected"
assert_eq "${tabfile}:1: workaround comment without a link" "$(head -1 <<<"$out")" "reports tab-named file"
git -C "$repo" rm -q -- "$tabfile"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "remove tab-named file"

# Deleting a non-comment line adjacent to an existing unlinked workaround ignores it,
# whereas deleting the link line from a linked workaround block flags the survivor. no-link: test prose.
sed -i '/x = 42;/d' "$repo/unlinked.nix"
git -C "$repo" add unlinked.nix
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "delete code line near workaround"
out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "deleting code outside a workaround block does not flag it"

sed -i '/https:\/\/github.com\/NixOS\/nixpkgs\/pull\/1/d' "$repo/linked.nix"
git -C "$repo" add linked.nix
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "delete link line from workaround"
out=$("$tool" --base HEAD~1 "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "deleting only the link line from a workaround block flags the block"
assert_eq "linked.nix:2: workaround comment without a link" "$(head -1 <<<"$out")" "reports surviving unlinked block"
git -C "$repo" checkout -q HEAD~1 -- linked.nix
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m "restore linked.nix"

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

echo "== whole words"
cat >"$repo/words.nix" <<'NIX'
{
  # These upstream fixtures need store interpreters.
  a = 1;
  # Appended at normal priority, so a consumer could only drop them with mkForce.
  b = 2;
  # Pinned until upstream fixes the build.
  c = 3;
  # Two workarounds for the sandbox.
  d = 4;
}
NIX
git -C "$repo" add -A
out=$("$tool" "$repo" -- words.nix 2>&1) && rc=0 || rc=$?
assert_eq "words.nix:6: workaround comment without a link" "$(head -1 <<<"$out")" "a phrase inside a longer word doesn't count"
assert_eq "2 workaround comments, 2 without a link" "$(tail -1 <<<"$out")" "plurals still count"

echo "== --states (stub gh)"
# A stub, so the test doesn't depend on the live state of a GitHub item.
mkdir -p "$repo.bin"
# shellcheck disable=SC2016 # the stub's own $1
printf '#!/usr/bin/env bash\n[ "$1" = pr ] && { echo MERGED; exit 0; }\nexit 1\n' >"$repo.bin/gh"
chmod +x "$repo.bin/gh"
printf '# Workaround, drop once kleinbem/nix-toolbox#1 is in.\n' >"$repo/merged.nix"
git -C "$repo" add -A
out=$(PATH="$repo.bin:$PATH" "$tool" --states "$repo" -- merged.nix 2>&1) && rc=0 || rc=$?
assert_eq "merged.nix:1: https://github.com/kleinbem/nix-toolbox/issues/1 is MERGED; drop the workaround once the fix is in what we use" \
    "$(head -1 <<<"$out")" "a merged PR behind owner/repo#N is reported"

echo "== heredocs, an empty no-link and a bad base"
cat >"$repo/fixture.sh" <<'SH'
cat >x <<'EOF2'
# Workaround with no link, but only fixture data.
EOF2
true # workaround no-link:
SH
git -C "$repo" add -A
out=$("$tool" "$repo" -- fixture.sh 2>&1) && rc=0 || rc=$?
assert_eq "fixture.sh:4: workaround comment without a link" "$(head -1 <<<"$out")" "heredoc body skipped, no-link needs a reason"
out=$("$tool" --base no-such-rev "$repo" 2>&1) && rc=0 || rc=$?
assert_eq 2 "$rc" "an unknown --base revision is an error, not a pass"

echo "== arithmetic shifts and git errors"
cat >"$repo/shift.sh" <<'SH'
value=$((1 << shift))
# Workaround without a link after a shift.
true
n=$((n + 1)); cat <<'EOF2'
# Workaround in fixture data after a closed arithmetic expansion.
EOF2
SH
git -C "$repo" add -A
out=$("$tool" "$repo" -- shift.sh 2>&1) && rc=0 || rc=$?
assert_eq "shift.sh:2: workaround comment without a link" "$(head -1 <<<"$out")" "a shift is no heredoc"
out=$("$tool" "$repo" -- ':(bogus)x' 2>&1) && rc=0 || rc=$?
assert_eq 2 "$rc" "a git error (bad pathspec) is an error, not a pass"

echo "== symlinks"
ln -s ../elsewhere/missing.just "$repo/dangling.just"
ln -s unlinked.nix "$repo/alias.nix"
git -C "$repo" add -A
out=$("$tool" "$repo" -- '*.just' alias.nix 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "dangling and in-repo symlinks are skipped"

echo "== pathspec"
out=$("$tool" "$repo" -- script.sh 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "pathspec limits the files"

echo "== test skips"
cat >"$repo/skips.nix" <<'NIX'
{
  checkFlags = [
    # Needs network access.
    "--skip=net::fetches"
    # Polls /bin/kill, which the sandbox lacks.
    # upstream: block/buzz#9530
    "--skip=proc::kill"
  ];
  cargoTestFlags = [
    # no-link: only the CLI is installed.
    "--exclude"
    "xtask"
    # Hangs on builders; drop once upstream fixes it.
    "--exclude"
    "flaky"
  ];
  # Ordinary comment above an ordinary line.
  doCheck = true;
}
NIX
git -C "$repo" add -A
out=$("$tool" "$repo" -- skips.nix 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "a skip that waits on upstream without a link fails"
assert_eq "skips.nix:13: workaround comment without a link" "$(head -1 <<<"$out")" "a skip comment announcing a workaround needs a link"
assert_empty "$(grep -F 'skips.nix:3:' <<<"$out" || true)" "a skip comment giving a reason passes"
assert_eq "4 workaround comments, 1 without a link" "$(tail -1 <<<"$out")" "reason, linked, no-link and announced comments are told apart"

echo "== --base: a new skip under an old comment"
printf '{\n  # Flaky on builders until upstream fixes it.\n  doCheck = true;\n}\n' >"$repo/oldcomment.nix"
git -C "$repo" add -A
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m oldcomment
sed -i 's/doCheck = true/doCheck = false/' "$repo/oldcomment.nix"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -am skip
out=$("$tool" --base HEAD~1 "$repo" -- oldcomment.nix 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "disabling the tests under an unchanged unlinked comment fails"
assert_eq "oldcomment.nix:2: workaround comment without a link" "$(head -1 <<<"$out")" "reported at the comment"

echo "== unquoted flags are commands, not test skips"
printf '#!/bin/sh\n# Keep the archive small.\ntar --exclude=.git -cf x.tar .\n' >"$repo/pack.sh"
git -C "$repo" add -A
out=$("$tool" "$repo" -- pack.sh 2>&1) && rc=0 || rc=$?
assert_eq 0 "$rc" "a comment above tar --exclude is no workaround"

echo "== more files than one command line takes"
mkdir "$repo/many"
for i in $(seq 1 4000); do printf '{ }\n' >"$repo/many/file-with-a-long-name-to-fill-the-argument-list-$i.nix"; done
printf '# workaround without a link\n{ }\n' >"$repo/many/zz-last.nix"
git -C "$repo" add -A
out=$( (ulimit -s 1024; "$tool" "$repo" -- 'many/*.nix') 2>&1) && rc=0 || rc=$?
assert_eq 1 "$rc" "every batch is scanned"
assert_eq "many/zz-last.nix:1: workaround comment without a link" "$(head -1 <<<"$out")" "a workaround in a later batch is found"
assert_empty "$(grep -i 'argument list too long' <<<"$out" || true)" "no ARG_MAX failure"

test_summary
