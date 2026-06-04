#!/bin/bash
# Fake tar for offline tests. Simulates extraction of the downloaded tarball by
# writing a .yang file under the directory given by -C, nested like the real
# repos. Honours $TAR_STUB_NOS (sros under YANG/, srlinux under
# srlinux-yang-models/srl_nokia/). The tarball file (-f) is ignored.
dir=""
while (( $# )); do
  case "$1" in
    -C) dir=$2; shift 2 ;;
    *)  shift ;;
  esac
done

[[ -z $dir ]] && exit 0
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
