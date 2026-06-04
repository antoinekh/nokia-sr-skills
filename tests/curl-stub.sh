#!/bin/bash
# Fake curl for offline tests. Two modes, keyed off the URL:
#   .../tags?...        -> emit $CURL_STUB_TAGS_JSON on stdout (for resolve_latest)
#   .../tarball/<ref>   -> write fake tarball bytes to the -o file (for fetch_yang)
# Logs each invocation to $CURL_STUB_LOG. Exits 22 (like curl -f on HTTP error),
# writing a message to stderr, for any ref in $CURL_STUB_FAIL_REFS.
printf '%s\n' "$*" >> "${CURL_STUB_LOG:-/dev/null}"

outfile="" url=""
while (( $# )); do
  case "$1" in
    -o)               outfile=$2; shift 2 ;;
    -H|-A)            shift 2 ;;
    http://*|https://*) url=$1; shift ;;
    *)                shift ;;
  esac
done

if [[ $url == *"/tags"* ]]; then
  printf '%s' "${CURL_STUB_TAGS_JSON:-[]}"
  exit 0
fi

ref=${url##*/}
for f in ${CURL_STUB_FAIL_REFS:-}; do
  if [[ $ref == "$f" ]]; then
    echo "curl: (22) The requested URL returned error: 404" >&2
    exit 22
  fi
done

if [[ -n $outfile ]]; then
  printf 'FAKE_TARBALL\n' > "$outfile"
else
  printf 'FAKE_TARBALL\n'
fi
exit 0
