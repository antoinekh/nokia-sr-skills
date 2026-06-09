#!/bin/bash
# Plain-bash test suite for ensure-yang.sh. Sources the script for unit tests and
# execs it (with stubbed curl + tar on PATH) for integration tests. No network, no bats.
#
# shellcheck disable=SC2015,SC2030,SC2031
# SC2015: '&& pass || fail' is safe here - pass() never fails.
# SC2030/SC2031: env changes being local to each ( ) subshell is the point - it is
# how tests stay isolated from each other.
set -uo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SUT="$TEST_DIR/../skills/nokia-sr/scripts/ensure-yang.sh"
# Failures are recorded in a file, not a counter: most tests run in ( ) subshells,
# where a counter increment would be lost and the suite would wrongly exit 0.
FAIL_FLAG=$(mktemp)
trap 'rm -f "$FAIL_FLAG"' EXIT

pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s (expected [%s] got [%s])\n' "$1" "$3" "$2"; echo "$1" >> "$FAIL_FLAG"; }
assert_eq() { [[ $2 == "$3" ]] && pass "$1" || fail "$1" "$2" "$3"; }

# Fresh sandbox HOME + stubbed curl/tar on PATH for one integration run.
make_sandbox() {
  SANDBOX=$(mktemp -d)
  mkdir -p "$SANDBOX/bin"
  cp "$TEST_DIR/curl-stub.sh" "$SANDBOX/bin/curl"
  cp "$TEST_DIR/tar-stub.sh" "$SANDBOX/bin/tar"
  chmod +x "$SANDBOX/bin/curl" "$SANDBOX/bin/tar"
  export CURL_STUB_LOG="$SANDBOX/curl.log"
  : > "$CURL_STUB_LOG"
  unset CURL_STUB_FAIL_REFS TAR_STUB_NOS GITHUB_TOKEN GH_TOKEN
}

# --- unit: source the script, call pure functions directly ---
unset GITHUB_TOKEN GH_TOKEN  # keep CURL_OPTS deterministic regardless of caller env
# shellcheck disable=SC1090
source "$SUT"

# sros version parsing
normalize_version sros "25.10.R4"
assert_eq "sros canon from 25.10.R4"   "$CANON_VER"  "25.10.R4"
assert_eq "sros repo"                  "$REPO"       "nokia/7x50_YangModels"
assert_eq "sros refs from 25.10.R4"    "${REFS[*]}"  "sros_25.10.r4 sros_25.10"

normalize_version sros "25.10.r4"
assert_eq "sros canon from lowercase"  "$CANON_VER"  "25.10.R4"
assert_eq "sros refs from lowercase"   "${REFS[*]}"  "sros_25.10.r4 sros_25.10"

if normalize_version sros "25.10"; then
  fail "reject bare sros version (no revision)" "accepted" "rejected"; else pass "reject bare sros version (no revision)"; fi

normalize_version sros "  25.10.R4  "
assert_eq "sros trims whitespace"      "$CANON_VER"  "25.10.R4"

# srlinux version parsing
normalize_version srlinux "25.10.3"
assert_eq "srlinux canon from 25.10.3" "$CANON_VER"  "25.10.3"
assert_eq "srlinux repo"               "$REPO"       "nokia/srlinux-yang-models"
assert_eq "srlinux refs from 25.10.3"  "${REFS[*]}"  "v25.10.3"

normalize_version srlinux "v25.10.3"
assert_eq "srlinux canon from v-prefix" "$CANON_VER" "25.10.3"

if normalize_version sros "garbage"; then
  fail "reject garbage sros version" "accepted" "rejected"; else pass "reject garbage sros version"; fi

if normalize_version srlinux "25.10"; then
  fail "reject 2-part srlinux version" "accepted" "rejected"; else pass "reject 2-part srlinux version"; fi

normalize_version frobnos "25.10.R4"; rc=$?
assert_eq "unknown nos returns 2" "$rc" "2"

set_repo frobnos; assert_eq "set_repo unknown nos returns 2" "$?" "2"

# resolve_latest picks the highest version from the tags API (stubbed curl)
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"
  export CURL_STUB_TAGS_JSON='[{"name":"sros_25.10.r4"},{"name":"sros_26.3.r3"},{"name":"sros_26.3.r1"},{"name":"junk"}]'
  set_repo sros
  out=$(resolve_latest sros)
  assert_eq "latest: sros newest tag" "$out" "26.3.r3" )

( make_sandbox; export PATH="$SANDBOX/bin:$PATH"
  export CURL_STUB_TAGS_JSON='[{"name":"v25.10.3"},{"name":"v26.3.1"},{"name":"v25.7.2"}]'
  set_repo srlinux
  out=$(resolve_latest srlinux)
  assert_eq "latest: srlinux newest tag" "$out" "26.3.1" )

# resolve_cache_dir honours explicit override
( export NOKIA_SR_YANG_DIR="/tmp/override"; resolve_cache_dir
  assert_eq "cache: explicit override" "$CACHE_DIR" "/tmp/override" )

# falls back to the dedicated XDG cache when no override is set
( make_sandbox; export HOME="$SANDBOX"; unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
  resolve_cache_dir
  assert_eq "cache: xdg fallback" "$CACHE_DIR" "$HOME/.cache/nokia-sr/yang" )

# finds a populated tree (recursively)
( make_sandbox; CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"
  mkdir -p "$CACHE_DIR/sros/25.10.R4/YANG"
  printf 'module x { }\n' > "$CACHE_DIR/sros/25.10.R4/YANG/x.yang"
  out=$(find_existing_yang sros); rc=$?
  assert_eq "presence: found rc" "$rc" "0"
  assert_eq "presence: release dir path" "$out" "$CACHE_DIR/sros/25.10.R4" )

# empty dir (no .yang files) is NOT a hit
( make_sandbox; CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"
  mkdir -p "$CACHE_DIR/sros/25.10.R4/YANG"
  if find_existing_yang sros > /dev/null; then
    fail "presence: empty dir miss" "found" "miss"; else pass "presence: empty dir miss"; fi )

# fetch sros uses the tag ref first
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REFS=(sros_25.10.r4 sros_25.10)
  out=$(fetch_yang sros)
  assert_eq "fetch: returns release path" "$out" "$CACHE_DIR/sros/25.10.R4"
  grep -q -- "tarball/sros_25.10.r4" "$CURL_STUB_LOG" \
    && pass "fetch: used tag ref" || fail "fetch: used tag ref" "missing" "present" )

# fetch falls back to the branch ref when the tag download fails
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"; export CURL_STUB_FAIL_REFS="sros_25.10.r4"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REFS=(sros_25.10.r4 sros_25.10)
  out=$(fetch_yang sros)
  assert_eq "fetch: fallback release path" "$out" "$CACHE_DIR/sros/25.10.R4"
  grep -q -- "tarball/sros_25.10$" "$CURL_STUB_LOG" \
    && pass "fetch: used branch fallback" || fail "fetch: used branch fallback" "missing" "present" )

# a failed (re)fetch must not destroy an existing good cache (atomic temp+rename).
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"; export CURL_STUB_FAIL_REFS="sros_25.10.r4 sros_25.10"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REFS=(sros_25.10.r4 sros_25.10)
  good="$CACHE_DIR/sros/25.10.R4/YANG"; mkdir -p "$good"; printf 'module x { }\n' > "$good/x.yang"
  fetch_yang sros > /dev/null 2>&1; rc=$?
  assert_eq "fetch: failed refresh exit 1" "$rc" "1"
  [[ -f $good/x.yang ]] && pass "fetch: failed refresh preserves existing cache" \
                        || fail "fetch: failed refresh preserves existing cache" "destroyed" "preserved" )

# a successful fetch leaves no leftover temp dir behind.
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REFS=(sros_25.10.r4 sros_25.10)
  fetch_yang sros > /dev/null
  leftover=$(find "$CACHE_DIR/sros" -maxdepth 1 -name '25.10.R4.tmp.*' -print -quit 2>/dev/null)
  [[ -z $leftover ]] && pass "fetch: no leftover temp dir" \
                     || fail "fetch: no leftover temp dir" "$leftover" "none" )

# fetch srlinux uses the v-tag and nests like the real repo
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"; export TAR_STUB_NOS="srlinux"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.3"; REPO="nokia/srlinux-yang-models"
  REFS=(v25.10.3)
  out=$(fetch_yang srlinux)
  assert_eq "fetch: srlinux release path" "$out" "$CACHE_DIR/srlinux/25.10.3"
  grep -q -- "tarball/v25.10.3" "$CURL_STUB_LOG" \
    && pass "fetch: srlinux used v-tag" || fail "fetch: srlinux used v-tag" "missing" "present"
  [[ -n $(find "$out" -name '*.yang' -print -quit) ]] \
    && pass "fetch: srlinux extracted yang" || fail "fetch: srlinux extracted yang" "none" "present" )

# end-to-end: sros missing -> fetches -> prints path, exit 0
( make_sandbox; export HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH"
  unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
  out=$(bash "$SUT" sros 25.10.R4); rc=$?
  assert_eq "e2e: sros exit 0 on fetch" "$rc" "0"
  assert_eq "e2e: sros prints xdg path" "$out" "$HOME/.cache/nokia-sr/yang/sros/25.10.R4" )

# end-to-end: srlinux missing -> fetches -> prints path, exit 0
( make_sandbox; export HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH" TAR_STUB_NOS="srlinux"
  unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
  out=$(bash "$SUT" srlinux v25.10.3); rc=$?
  assert_eq "e2e: srlinux exit 0 on fetch" "$rc" "0"
  assert_eq "e2e: srlinux prints xdg path" "$out" "$HOME/.cache/nokia-sr/yang/srlinux/25.10.3" )

# end-to-end: already present -> prints path, does NOT call curl
( make_sandbox; export HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH"
  unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
  d="$HOME/.cache/nokia-sr/yang/sros/25.10.R4/YANG"; mkdir -p "$d"; printf 'module x { }\n' > "$d/x.yang"
  out=$(bash "$SUT" sros 25.10.R4); rc=$?
  assert_eq "e2e: exit 0 when present" "$rc" "0"
  assert_eq "e2e: returns existing path" "$out" "$HOME/.cache/nokia-sr/yang/sros/25.10.R4"
  [[ -s $CURL_STUB_LOG ]] && fail "e2e: skips curl when present" "called" "skipped" \
                          || pass "e2e: skips curl when present" )

# end-to-end: latest -> resolves newest tag, fetches, prints path
( make_sandbox; export HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH"
  unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
  export CURL_STUB_TAGS_JSON='[{"name":"sros_25.10.r4"},{"name":"sros_26.3.r3"}]'
  out=$(bash "$SUT" sros latest); rc=$?
  assert_eq "e2e: latest exit 0" "$rc" "0"
  assert_eq "e2e: latest resolves newest path" "$out" "$HOME/.cache/nokia-sr/yang/sros/26.3.R3" )

# bad version -> exit 2
( out=$(bash "$SUT" sros garbage 2>/dev/null); rc=$?
  assert_eq "e2e: exit 2 on bad version" "$rc" "2" )

# bare sros version (no revision) -> exit 2
( bash "$SUT" sros 25.10 > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on bare sros version" "$rc" "2" )

# unknown nos -> exit 2
( bash "$SUT" frobnos 25.10.R4 > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on unknown nos" "$rc" "2" )

# missing args -> exit 2, usage on stderr
( bash "$SUT" sros > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on missing version" "$rc" "2" )
( err=$(bash "$SUT" 2>&1 >/dev/null); rc=$?
  assert_eq "e2e: exit 2 on no args" "$rc" "2"
  case "$err" in
    *"Usage: ensure-yang.sh"*) pass "e2e: no args prints usage on stderr" ;;
    *) fail "e2e: no args prints usage on stderr" "$err" "contains 'Usage: ensure-yang.sh'" ;;
  esac )

# --help / -h -> usage on stdout, exit 0
( out=$(bash "$SUT" --help); rc=$?
  assert_eq "e2e: --help exits 0" "$rc" "0"
  case "$out" in
    *"Usage: ensure-yang.sh"*) pass "e2e: --help prints usage" ;;
    *) fail "e2e: --help prints usage" "$out" "contains 'Usage: ensure-yang.sh'" ;;
  esac )
( bash "$SUT" -h > /dev/null; rc=$?
  assert_eq "e2e: -h exits 0" "$rc" "0" )

# GITHUB_TOKEN -> Authorization header on every GitHub request
( make_sandbox; export HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH" GITHUB_TOKEN="t0ken"
  unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
  bash "$SUT" sros 25.10.R4 > /dev/null
  grep -q -- "Authorization: Bearer t0ken" "$CURL_STUB_LOG" \
    && pass "e2e: token sent as Authorization header" \
    || fail "e2e: token sent as Authorization header" "missing" "present" )

# no token -> no Authorization header
( make_sandbox; export HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH"
  unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
  bash "$SUT" sros 25.10.R4 > /dev/null
  grep -q -- "Authorization:" "$CURL_STUB_LOG" \
    && fail "e2e: no Authorization header without token" "present" "absent" \
    || pass "e2e: no Authorization header without token" )

# relative cache dir is rejected (rm -rf safety guard)
( export NOKIA_SR_YANG_DIR="relative/cache"
  bash "$SUT" sros 25.10.R4 > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on relative cache dir" "$rc" "2" )

# root '/' cache dir is rejected (rm -rf safety guard)
( export NOKIA_SR_YANG_DIR="/"
  bash "$SUT" sros 25.10.R4 > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on root cache dir" "$rc" "2" )

# total download failure surfaces a diagnostic and exits 1
( make_sandbox; export HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH"
  unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
  export CURL_STUB_FAIL_REFS="sros_25.10.r4 sros_25.10"
  err=$(bash "$SUT" sros 25.10.R4 2>&1 >/dev/null); rc=$?
  assert_eq "e2e: exit 1 when all downloads fail" "$rc" "1"
  case "$err" in
    *"failed to fetch"*) pass "e2e: surfaces fetch error" ;;
    *) fail "e2e: surfaces fetch error" "$err" "contains 'failed to fetch'" ;;
  esac
  case "$err" in
    *"curl:"*"404"*) pass "e2e: surfaces curl's real error" ;;
    *) fail "e2e: surfaces curl's real error" "$err" "contains curl 404" ;;
  esac )

echo
FAILS=$(wc -l < "$FAIL_FLAG")
if (( FAILS > 0 )); then
  printf '%d test(s) failed\n' "$FAILS"; exit 1
fi
echo "all tests passed"
