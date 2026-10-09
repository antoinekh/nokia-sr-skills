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
# One root for every temp file and sandbox, removed on exit.
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
# Failures are recorded in a file, not a counter: most tests run in ( ) subshells,
# where a counter increment would be lost and the suite would wrongly exit 0.
FAIL_FLAG="$TEST_TMP/failures"
: > "$FAIL_FLAG"

pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s (expected [%s] got [%s])\n' "$1" "$3" "$2"; echo "$1" >> "$FAIL_FLAG"; }
assert_eq() { [[ $2 == "$3" ]] && pass "$1" || fail "$1" "$2" "$3"; }

# Fresh sandbox HOME + stubbed curl/tar on PATH for one integration run.
make_sandbox() {
  SANDBOX=$(mktemp -d -p "$TEST_TMP")
  mkdir -p "$SANDBOX/bin"
  cp "$TEST_DIR/curl-stub.sh" "$SANDBOX/bin/curl"
  cp "$TEST_DIR/tar-stub.sh" "$SANDBOX/bin/tar"
  chmod +x "$SANDBOX/bin/curl" "$SANDBOX/bin/tar"
  export CURL_STUB_LOG="$SANDBOX/curl.log"
  : > "$CURL_STUB_LOG"
  unset CURL_STUB_FAIL_REFS CURL_STUB_SLEEP CURL_STUB_TAGS_FAIL TAR_STUB_NOS TAR_STUB_MODE GITHUB_TOKEN GH_TOKEN
}

# make_sandbox, plus HOME and the stubbed PATH, so a run of the script stays offline and isolated.
make_e2e_sandbox() {
  make_sandbox
  export HOME="$SANDBOX" PATH="$SANDBOX/bin:$PATH"
  unset NOKIA_SR_YANG_DIR XDG_CACHE_HOME
}

# --- unit: source the script, call pure functions directly ---
unset GITHUB_TOKEN GH_TOKEN  # keep CURL_OPTS deterministic regardless of caller env
# shellcheck disable=SC1090
source "$SUT"

# sros version parsing
normalize_version sros "25.10.R4"
assert_eq "sros canon from 25.10.R4"   "$CANON_VER"  "25.10.R4"
assert_eq "sros ref from 25.10.R4"     "$REF"        "sros_25.10.r4"

normalize_version sros "25.10.r4"
assert_eq "sros canon from lowercase"  "$CANON_VER"  "25.10.R4"
assert_eq "sros ref from lowercase"    "$REF"        "sros_25.10.r4"

if normalize_version sros "25.10"; then
  fail "reject bare sros version (no revision)" "accepted" "rejected"; else pass "reject bare sros version (no revision)"; fi

normalize_version sros "  25.10.R4  "
assert_eq "sros trims whitespace"      "$CANON_VER"  "25.10.R4"

# srlinux version parsing
normalize_version srlinux "25.10.3"
assert_eq "srlinux canon from 25.10.3" "$CANON_VER"  "25.10.3"
assert_eq "srlinux ref from 25.10.3"   "$REF"        "v25.10.3"

normalize_version srlinux "v25.10.3"
assert_eq "srlinux canon from v-prefix" "$CANON_VER" "25.10.3"

if normalize_version sros "garbage"; then
  fail "reject garbage sros version" "accepted" "rejected"; else pass "reject garbage sros version"; fi

if normalize_version srlinux "25.10"; then
  fail "reject 2-part srlinux version" "accepted" "rejected"; else pass "reject 2-part srlinux version"; fi

normalize_version frobnos "25.10.R4"; rc=$?
assert_eq "unknown nos returns 2" "$rc" "2"

set_repo sros;    assert_eq "set_repo sros"    "$REPO" "nokia/7x50_YangModels"
set_repo srlinux; assert_eq "set_repo srlinux" "$REPO" "nokia/srlinux-yang-models"
set_repo frobnos; assert_eq "set_repo unknown nos returns 2" "$?" "2"

# one_line_error joins a multi-line error and falls back when the file is empty
( make_sandbox
  printf 'curl: (22) 404\n\n' > "$SANDBOX/err"
  assert_eq "error: one trimmed line" "$(one_line_error "$SANDBOX/err" fallback)" "curl: (22) 404"
  : > "$SANDBOX/err"
  assert_eq "error: empty file -> fallback" "$(one_line_error "$SANDBOX/err" fallback)" "fallback" )

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

# fetch sros uses the revision tag
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REF=sros_25.10.r4
  out=$(fetch_yang sros)
  assert_eq "fetch: returns release path" "$out" "$CACHE_DIR/sros/25.10.R4"
  grep -q -- "tarball/sros_25.10.r4" "$CURL_STUB_LOG" \
    && pass "fetch: used tag ref" || fail "fetch: used tag ref" "missing" "present" )

# a missing revision tag fails: the branch holds another revision, so it is never fetched
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"; export CURL_STUB_FAIL_REFS="sros_25.10.r4"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REF=sros_25.10.r4
  fetch_yang sros > /dev/null 2>&1; rc=$?
  assert_eq "fetch: missing tag exit 1" "$rc" "1"
  grep -q -- "tarball/sros_25.10$" "$CURL_STUB_LOG" \
    && fail "fetch: never fetches the branch" "fetched" "not fetched" \
    || pass "fetch: never fetches the branch"
  [[ -d $CACHE_DIR/sros/25.10.R4 ]] \
    && fail "fetch: missing tag caches nothing" "cached" "absent" \
    || pass "fetch: missing tag caches nothing" )

# a failed (re)fetch must not destroy an existing good cache (atomic temp+rename).
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"; export CURL_STUB_FAIL_REFS="sros_25.10.r4"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REF=sros_25.10.r4
  good="$CACHE_DIR/sros/25.10.R4/YANG"; mkdir -p "$good"; printf 'module x { }\n' > "$good/x.yang"
  fetch_yang sros > /dev/null 2>&1; rc=$?
  assert_eq "fetch: failed refresh exit 1" "$rc" "1"
  [[ -f $good/x.yang ]] && pass "fetch: failed refresh preserves existing cache" \
                        || fail "fetch: failed refresh preserves existing cache" "destroyed" "preserved" )

# a successful fetch leaves no leftover temp dir behind.
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REF=sros_25.10.r4
  fetch_yang sros > /dev/null
  leftover=$(find "$CACHE_DIR/sros" -maxdepth 1 -name '25.10.R4.tmp.*' -print -quit 2>/dev/null)
  [[ -z $leftover ]] && pass "fetch: no leftover temp dir" \
                     || fail "fetch: no leftover temp dir" "$leftover" "none" )

# a tar failure exits 1 with tar's own error and caches nothing
( make_sandbox; export PATH="$SANDBOX/bin:$PATH" TAR_STUB_MODE=fail
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REF=sros_25.10.r4
  err=$(fetch_yang sros 2>&1 >/dev/null); rc=$?
  assert_eq "fetch: tar failure exit 1" "$rc" "1"
  case "$err" in
    *"does not look like a tar archive"*) pass "fetch: surfaces tar's error" ;;
    *) fail "fetch: surfaces tar's error" "$err" "contains tar's message" ;;
  esac
  leftover=$(find "$CACHE_DIR/sros" -mindepth 1 -print -quit 2>/dev/null)
  [[ -z $leftover ]] && pass "fetch: tar failure leaves nothing" \
                     || fail "fetch: tar failure leaves nothing" "$leftover" "none" )

# a tarball without .yang files exits 1 and caches nothing
( make_sandbox; export PATH="$SANDBOX/bin:$PATH" TAR_STUB_MODE=empty
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.R4"; REPO="nokia/7x50_YangModels"
  REF=sros_25.10.r4
  err=$(fetch_yang sros 2>&1 >/dev/null); rc=$?
  assert_eq "fetch: no .yang exit 1" "$rc" "1"
  case "$err" in
    *"contained no .yang files"*) pass "fetch: reports a tarball without .yang" ;;
    *) fail "fetch: reports a tarball without .yang" "$err" "contains 'contained no .yang files'" ;;
  esac
  leftover=$(find "$CACHE_DIR/sros" -mindepth 1 -print -quit 2>/dev/null)
  [[ -z $leftover ]] && pass "fetch: no .yang leaves nothing" \
                     || fail "fetch: no .yang leaves nothing" "$leftover" "none" )

# fetch srlinux uses the v-tag and nests like the real repo
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"; export TAR_STUB_NOS="srlinux"
  CACHE_DIR="$SANDBOX/yang"; CANON_VER="25.10.3"; REPO="nokia/srlinux-yang-models"
  REF=v25.10.3
  out=$(fetch_yang srlinux)
  assert_eq "fetch: srlinux release path" "$out" "$CACHE_DIR/srlinux/25.10.3"
  grep -q -- "tarball/v25.10.3" "$CURL_STUB_LOG" \
    && pass "fetch: srlinux used v-tag" || fail "fetch: srlinux used v-tag" "missing" "present"
  [[ -n $(find "$out" -name '*.yang' -print -quit) ]] \
    && pass "fetch: srlinux extracted yang" || fail "fetch: srlinux extracted yang" "none" "present" )

# an interrupted download (signal to the whole process group, like Ctrl-C) leaves no temp files
( make_e2e_sandbox; export CURL_STUB_SLEEP=30
  setsid bash "$SUT" sros 25.10.R4 > /dev/null 2>&1 &
  pid=$!
  cache="$HOME/.cache/nokia-sr/yang/sros"
  for _ in {1..50}; do
    [[ -n $(find "$cache" -name '25.10.R4.tar.*' -print -quit 2>/dev/null) ]] && break
    sleep 0.1
  done
  kill -TERM -- "-$pid"; wait "$pid"
  leftover=$(find "$cache" -mindepth 1 -print -quit 2>/dev/null)
  [[ -z $leftover ]] && pass "e2e: interrupted download leaves no temp files" \
                     || fail "e2e: interrupted download leaves no temp files" "$leftover" "none" )

# end-to-end: sros missing -> fetches -> prints path, exit 0
( make_e2e_sandbox
  out=$(bash "$SUT" sros 25.10.R4); rc=$?
  assert_eq "e2e: sros exit 0 on fetch" "$rc" "0"
  assert_eq "e2e: sros prints xdg path" "$out" "$HOME/.cache/nokia-sr/yang/sros/25.10.R4" )

# end-to-end: srlinux missing -> fetches -> prints path, exit 0
( make_e2e_sandbox; export TAR_STUB_NOS="srlinux"
  out=$(bash "$SUT" srlinux v25.10.3); rc=$?
  assert_eq "e2e: srlinux exit 0 on fetch" "$rc" "0"
  assert_eq "e2e: srlinux prints xdg path" "$out" "$HOME/.cache/nokia-sr/yang/srlinux/25.10.3" )

# end-to-end: already present -> prints path, does NOT call curl
( make_e2e_sandbox
  d="$HOME/.cache/nokia-sr/yang/sros/25.10.R4/YANG"; mkdir -p "$d"; printf 'module x { }\n' > "$d/x.yang"
  out=$(bash "$SUT" sros 25.10.R4); rc=$?
  assert_eq "e2e: exit 0 when present" "$rc" "0"
  assert_eq "e2e: returns existing path" "$out" "$HOME/.cache/nokia-sr/yang/sros/25.10.R4"
  [[ -s $CURL_STUB_LOG ]] && fail "e2e: skips curl when present" "called" "skipped" \
                          || pass "e2e: skips curl when present" )

# end-to-end: latest -> resolves newest tag, fetches, prints path
( make_e2e_sandbox
  export CURL_STUB_TAGS_JSON='[{"name":"sros_25.10.r4"},{"name":"sros_26.3.r3"}]'
  out=$(bash "$SUT" sros latest); rc=$?
  assert_eq "e2e: latest exit 0" "$rc" "0"
  assert_eq "e2e: latest resolves newest path" "$out" "$HOME/.cache/nokia-sr/yang/sros/26.3.R3" )

# latest: an unreachable API exits 1 with a clear error and downloads nothing
( make_e2e_sandbox; export CURL_STUB_TAGS_FAIL=1
  err=$(bash "$SUT" sros latest 2>&1 >/dev/null); rc=$?
  assert_eq "e2e: latest exit 1 when the API fails" "$rc" "1"
  case "$err" in
    *"could not resolve latest sros version"*) pass "e2e: latest reports the API failure" ;;
    *) fail "e2e: latest reports the API failure" "$err" "contains 'could not resolve latest sros version'" ;;
  esac
  grep -q -- "/tarball/" "$CURL_STUB_LOG" \
    && fail "e2e: latest API failure downloads nothing" "downloaded" "nothing" \
    || pass "e2e: latest API failure downloads nothing" )

# latest: no tag of the NOS's version shape -> resolve_latest returns 1
( make_sandbox; export PATH="$SANDBOX/bin:$PATH"
  export CURL_STUB_TAGS_JSON='[{"name":"junk"},{"name":"sros_23.10.r6-1"}]'
  set_repo sros
  if resolve_latest sros > /dev/null; then
    fail "latest: no matching tag returns 1" "found" "none"; else pass "latest: no matching tag returns 1"; fi )

# bad version -> exit 2
( make_e2e_sandbox; out=$(bash "$SUT" sros garbage 2>/dev/null); rc=$?
  assert_eq "e2e: exit 2 on bad version" "$rc" "2" )

# bare sros version (no revision) -> exit 2
( make_e2e_sandbox; bash "$SUT" sros 25.10 > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on bare sros version" "$rc" "2" )

# unknown nos -> exit 2
( make_e2e_sandbox; bash "$SUT" frobnos 25.10.R4 > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on unknown nos" "$rc" "2" )

# missing args -> exit 2, usage on stderr
( make_e2e_sandbox; bash "$SUT" sros > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on missing version" "$rc" "2" )
( make_e2e_sandbox; err=$(bash "$SUT" 2>&1 >/dev/null); rc=$?
  assert_eq "e2e: exit 2 on no args" "$rc" "2"
  case "$err" in
    *"Usage: ensure-yang.sh"*) pass "e2e: no args prints usage on stderr" ;;
    *) fail "e2e: no args prints usage on stderr" "$err" "contains 'Usage: ensure-yang.sh'" ;;
  esac )

# --help / -h -> usage on stdout, exit 0
( make_e2e_sandbox; out=$(bash "$SUT" --help); rc=$?
  assert_eq "e2e: --help exits 0" "$rc" "0"
  case "$out" in
    *"Usage: ensure-yang.sh"*) pass "e2e: --help prints usage" ;;
    *) fail "e2e: --help prints usage" "$out" "contains 'Usage: ensure-yang.sh'" ;;
  esac )
( make_e2e_sandbox; bash "$SUT" -h > /dev/null; rc=$?
  assert_eq "e2e: -h exits 0" "$rc" "0" )

# GITHUB_TOKEN -> Authorization header on every GitHub request
( make_e2e_sandbox; export GITHUB_TOKEN="t0ken"
  bash "$SUT" sros 25.10.R4 > /dev/null
  grep -q -- "Authorization: Bearer t0ken" "$CURL_STUB_LOG" \
    && pass "e2e: token sent as Authorization header" \
    || fail "e2e: token sent as Authorization header" "missing" "present" )

# no token -> no Authorization header
( make_e2e_sandbox
  bash "$SUT" sros 25.10.R4 > /dev/null
  grep -q -- "Authorization:" "$CURL_STUB_LOG" \
    && fail "e2e: no Authorization header without token" "present" "absent" \
    || pass "e2e: no Authorization header without token" )

# relative cache dir is rejected (rm -rf safety guard)
( make_e2e_sandbox; export NOKIA_SR_YANG_DIR="relative/cache"
  bash "$SUT" sros 25.10.R4 > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on relative cache dir" "$rc" "2" )

# root '/' cache dir is rejected (rm -rf safety guard)
( make_e2e_sandbox; export NOKIA_SR_YANG_DIR="/"
  bash "$SUT" sros 25.10.R4 > /dev/null 2>&1; rc=$?
  assert_eq "e2e: exit 2 on root cache dir" "$rc" "2" )

# total download failure surfaces a diagnostic and exits 1
( make_e2e_sandbox
  export CURL_STUB_FAIL_REFS="sros_25.10.r4"
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
