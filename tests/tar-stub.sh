#!/bin/bash
# Fake tar for offline tests. Simulates extraction of the downloaded tarball by
# writing a .yang file under the directory given by -C, nested like the real
# repos. Honours $TAR_STUB_NOS (sros under YANG/, srlinux under
# srlinux-yang-models/srl_nokia/). The tarball file (-f) is ignored.
# $TAR_STUB_MODE=fail exits 2 like a corrupt archive; =empty extracts no .yang file.
dir=""
while (( $# )); do
  case "$1" in
    -C) dir=$2; shift 2 ;;
    *)  shift ;;
  esac
done

[[ -z $dir ]] && exit 0
case "${TAR_STUB_MODE:-}" in
  fail)
    echo "tar: This does not look like a tar archive" >&2
    exit 2
    ;;
  empty)
    mkdir -p "$dir/docs"
    printf 'readme\n' > "$dir/docs/README.md"
    exit 0
    ;;
esac
case "${TAR_STUB_NOS:-sros}" in
  srlinux)
    sub="$dir/srlinux-yang-models/srl_nokia"
    mkdir -p "$sub"
    printf 'module srl_nokia-system { }\n' > "$sub/srl_nokia-system.yang"
    ;;
  *)
    sub="$dir/YANG/nokia-combined"
    mkdir -p "$sub"
    printf 'module nokia-conf { }\n' > "$sub/nokia-conf.yang"
    ;;
esac
exit 0
