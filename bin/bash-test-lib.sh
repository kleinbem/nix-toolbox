# Shared assertion helpers for bash test scripts. Source this, run assert_*,
# then call test_summary: it prints the tally and exits non-zero on any failure.
# Deliberately tiny, so small test suites don't need bats.

_PASS=0
_FAIL=0

# assert_eq <expected> <actual> <description>
assert_eq() {
    local expected="$1" actual="$2" desc="$3"
    if [ "$expected" = "$actual" ]; then
        _PASS=$((_PASS + 1))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        _FAIL=$((_FAIL + 1))
        printf '  \033[31m✗\033[0m %s\n' "$desc"
        printf '      expected: %q\n' "$expected"
        printf '      actual:   %q\n' "$actual"
    fi
}

# assert_empty <actual> <description>
assert_empty() {
    assert_eq "" "$1" "$2"
}

test_summary() {
    echo
    if [ "$_FAIL" -eq 0 ]; then
        printf '\033[32m✅ %d/%d passed\033[0m\n' "$_PASS" "$((_PASS + _FAIL))"
        exit 0
    else
        printf '\033[31m❌ %d/%d passed, %d failed\033[0m\n' "$_PASS" "$((_PASS + _FAIL))" "$_FAIL"
        exit 1
    fi
}
