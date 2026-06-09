#!/bin/bash
# ensure-yang.sh - make Nokia SR YANG models available locally.
# Run with --help (or see usage() below) for arguments, environment, and sources.
#
# Downloads the matching release as a GitHub tarball - the same source the
# srpls language server / vscode-sr extension use - and caches it locally.
# Prints the local YANG release directory on stdout (grep it recursively).

GITHUB_API="https://api.github.com/repos"
CURL_OPTS=(-fsSL --retry 3 -H "Accept: application/vnd.github+json" -A "nokia-sr-skill")
# Unauthenticated api.github.com allows only 60 requests/hour per IP; a token lifts that.
if [[ -n ${GITHUB_TOKEN:-${GH_TOKEN:-}} ]]; then
  CURL_OPTS+=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
fi

usage() {
  cat << 'EOF'
Usage: ensure-yang.sh <nos> <version>

Make Nokia SR YANG models available locally: check the cache and download the
matching GitHub release tarball only if missing. Prints the local YANG release
directory on stdout (grep it recursively).

Arguments:
  nos      sros | srlinux
  version  sros:    MAJOR.MINOR.Rn        e.g. 25.10.R4 (a revision is required)
           srlinux: [v]MAJOR.MINOR.PATCH  e.g. 25.10.3 or v25.10.3
           either:  latest                resolve the newest release from GitHub

Options:
  -h, --help  Show this help and exit.

Environment:
  NOKIA_SR_YANG_DIR       Cache directory (default: ${XDG_CACHE_HOME:-~/.cache}/nokia-sr/yang).
  GITHUB_TOKEN / GH_TOKEN GitHub token sent as an Authorization header; lifts the
                          unauthenticated api.github.com rate limit (60 requests/hour per IP).

Sources:
  sros    -> github.com/nokia/7x50_YangModels      tag sros_<mm>.r<n> (branch sros_<mm> fallback)
  srlinux -> github.com/nokia/srlinux-yang-models  tag v<maj>.<min>.<patch>

Examples:
  ensure-yang.sh sros 25.10.R4
  ensure-yang.sh srlinux 25.10.3
  ensure-yang.sh sros latest
EOF
}

# set_repo <nos> -> sets REPO. Returns 2 for an unknown nos.
set_repo() {
  case $1 in
    sros)    REPO="nokia/7x50_YangModels" ;;
    srlinux) REPO="nokia/srlinux-yang-models" ;;
    *)       return 2 ;;
  esac
}

# normalize_version <nos> <version>
# Sets: REPO, CANON_VER (canonical version used for the cache dir),
#       REFS (ordered refs to try). Returns 1 on bad version, 2 on bad nos.
# A concrete version is required here - 'latest' is resolved earlier, in main.
normalize_version() {
  local nos=$1
  local raw=${2,,}
  # Trim surrounding whitespace so copy-pasted values (e.g. " 25.10.R4 ") still parse.
  raw=${raw#"${raw%%[![:space:]]*}"}
  raw=${raw%"${raw##*[![:space:]]}"}
  set_repo "$nos" || return 2
  REFS=()
  case $nos in
    sros)
      # Require an explicit revision (Rn): a bare 25.10 would pin to the moving
      # sros_25.10 branch and cache stale models, so reject it.
      if [[ $raw =~ ^([0-9]+\.[0-9]+)\.r([0-9]+)$ ]]; then
        local mm=${BASH_REMATCH[1]} rev=${BASH_REMATCH[2]}
        CANON_VER="${mm}.R${rev}"
        REFS+=("sros_${mm}.r${rev}" "sros_${mm}")  # revision tag, then branch as fallback
        return 0
      fi
      return 1
      ;;
    srlinux)
      if [[ $raw =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        CANON_VER="${BASH_REMATCH[1]}"
        REFS+=("v${CANON_VER}")  # yang files live only on the version tag, not main
        return 0
      fi
      return 1
      ;;
  esac
}

# resolve_latest <nos> -> echoes the newest concrete version (REPO must be set).
# Reads the GitHub tags API and picks the highest version with `sort -V`.
# Returns 1 if the API is unreachable or no matching tag is found.
resolve_latest() {
  local nos=$1 names ver=""
  names=$(curl "${CURL_OPTS[@]}" "$GITHUB_API/$REPO/tags?per_page=100" 2>/dev/null) || true
  [[ -z $names ]] && return 1
  local tags
  tags=$(printf '%s' "$names" | grep -oE '"name": *"[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/') || true
  case $nos in
    sros)    ver=$(printf '%s\n' "$tags" | grep -E '^sros_[0-9]+\.[0-9]+\.r[0-9]+$' | sed 's/^sros_//' | sort -V | tail -1) || true ;;
    srlinux) ver=$(printf '%s\n' "$tags" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'      | sed 's/^v//'      | sort -V | tail -1) || true ;;
  esac
  [[ -z $ver ]] && return 1
  printf '%s\n' "$ver"
}

# resolve_cache_dir -> sets CACHE_DIR (a dedicated cache, distinct from ~/.srpls).
resolve_cache_dir() {
  if [[ -n ${NOKIA_SR_YANG_DIR:-} ]]; then
    CACHE_DIR=$NOKIA_SR_YANG_DIR
  else
    CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/nokia-sr/yang"
  fi
}

# version_dir <nos> -> the release dir for CANON_VER inside the cache.
version_dir() {
  printf '%s\n' "$CACHE_DIR/$1/$CANON_VER"
}

# find_existing_yang <nos> -> prints the release dir if it holds .yang files. Returns 1 if not.
# Searches recursively because each NOS nests its modules differently
# (sros under YANG/, srlinux under srlinux-yang-models/srl_nokia/).
find_existing_yang() {
  local d
  d=$(version_dir "$1")
  if [[ -d $d ]] && [[ -n $(find "$d" -name '*.yang' -print -quit 2>/dev/null) ]]; then
    printf '%s\n' "$d"
    return 0
  fi
  return 1
}

# fetch_yang <nos> -> downloads the tarball for the first working ref and extracts
# it into the release dir; prints the dir. Returns 1 on failure.
# Downloads to a temp file (so curl's exit code and error are checked explicitly,
# not hidden behind a pipe) and extracts into a temp sibling, renaming atomically
# on success: a partial download never lands in the final path, so a failed
# re-fetch leaves a good cache untouched.
fetch_yang() {
  local nos=$1
  local dest tmp tarfile errfile
  dest=$(version_dir "$nos")
  tmp="${dest}.tmp.$$"
  tarfile="${dest}.tar.$$"
  errfile="${dest}.err.$$"
  mkdir -p "$CACHE_DIR/$nos"
  local ref err=""
  for ref in "${REFS[@]}"; do
    [[ -z $ref ]] && continue
    rm -rf "$tmp"; rm -f "$tarfile"
    local url="$GITHUB_API/$REPO/tarball/$ref"
    if ! curl "${CURL_OPTS[@]}" -o "$tarfile" "$url" 2> "$errfile"; then
      err=$(tr '\n' ' ' < "$errfile"); err=${err%"${err##*[![:space:]]}"}
      [[ -z $err ]] && err="curl failed for $url"
      continue
    fi
    mkdir -p "$tmp"
    # GitHub's tarball has a single top-level dir; --strip-components=1 drops it
    # so modules land directly under the release dir, like the language server.
    if ! tar -xzf "$tarfile" --strip-components=1 -C "$tmp" 2> "$errfile"; then
      err=$(tr '\n' ' ' < "$errfile"); err=${err%"${err##*[![:space:]]}"}
      [[ -z $err ]] && err="tar failed to extract $url"
      continue
    fi
    if [[ -n $(find "$tmp" -name '*.yang' -print -quit 2>/dev/null) ]]; then
      rm -f "$tarfile" "$errfile"
      rm -rf "$dest"
      mv "$tmp" "$dest"
      printf '%s\n' "$dest"
      return 0
    fi
    err="ref '$ref' contained no .yang files"
  done
  rm -rf "$tmp"; rm -f "$tarfile" "$errfile"
  # Surface the diagnostic so a network/DNS/TLS/404 failure is distinguishable from a bad version.
  [[ -n $err ]] && printf 'download: %s\n' "$err" >&2
  return 1
}

main() {
  set -euo pipefail
  case ${1:-} in
    -h|--help) usage; exit 0 ;;
  esac
  local nos=${1:-} version=${2:-}
  if [[ -z $nos || -z $version ]]; then
    usage >&2
    exit 2
  fi
  if ! set_repo "$nos"; then
    echo "error: unknown nos '$nos' (expected 'sros' or 'srlinux')" >&2
    exit 2
  fi

  if [[ ${version,,} == "latest" ]]; then
    local latest
    latest=$(resolve_latest "$nos") || { echo "error: could not resolve latest $nos version (network/API issue?)" >&2; exit 1; }
    version=$latest
  fi

  local rc=0
  normalize_version "$nos" "$version" || rc=$?
  if (( rc != 0 )); then
    echo "error: cannot parse $nos version '$version' (sros needs MAJOR.MINOR.Rn e.g. 25.10.R4; srlinux needs MAJOR.MINOR.PATCH e.g. 25.10.3)" >&2
    exit 2
  fi

  resolve_cache_dir
  # Guard the rm -rf in fetch_yang: only ever operate under an absolute, non-root cache dir.
  if [[ $CACHE_DIR != /* || $CACHE_DIR == "/" ]]; then
    echo "error: cache dir must be an absolute path other than '/' (got '$CACHE_DIR'). Check NOKIA_SR_YANG_DIR." >&2
    exit 2
  fi

  local existing
  if existing=$(find_existing_yang "$nos"); then
    printf '%s\n' "$existing"
    exit 0
  fi

  local manual
  manual="curl -fsSL $GITHUB_API/$REPO/tarball/${REFS[0]} -o /tmp/yang.tar.gz && mkdir -p $(version_dir "$nos") && tar -xz --strip-components=1 -f /tmp/yang.tar.gz -C $(version_dir "$nos")"
  if ! command -v curl > /dev/null 2>&1 || ! command -v tar > /dev/null 2>&1; then
    echo "error: need both 'curl' and 'tar'. Install them, or fetch manually:" >&2
    echo "  $manual" >&2
    exit 1
  fi

  local result
  if result=$(fetch_yang "$nos"); then
    printf '%s\n' "$result"
    exit 0
  fi

  echo "error: failed to fetch $nos YANG for ${CANON_VER}. Fetch manually:" >&2
  echo "  $manual" >&2
  exit 1
}

# Run main only when executed directly, so tests can source pure functions.
if [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main "$@"
fi
