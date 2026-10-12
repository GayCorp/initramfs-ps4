#!/bin/sh

set -eu

SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="${SRC}/initramfs.cpio.gz"

for arg in "$@"; do
    case "$arg" in
        -production|--production)
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [-production]" >&2
            exit 1
            ;;
    esac
done

cd "$SRC"

rm -f "$OUT"

chmod +x ./init ./bin/* ./hooks/*/* ./etc/profile.d/* 2>/dev/null || true
git rev-parse --short=7 HEAD 2>/dev/null > GIT_HASH || echo unknown > GIT_HASH

find . -mindepth 1 \( \
        -path ./bake.sh \
        -o -path ./initramfs.cpio.gz \
        -o -path ./README.md \
        -o -path ./.git \
        -o -path ./.github \
        -o -path ./.gitignore \
        -o -path ./.gitattributes \
    \) -prune -o -print0 \
| LC_ALL=C sort -z \
| cpio --null -o -H newc -R 0:0 --quiet \
| gzip -9 > "$OUT"

echo "Wrote $OUT ($(du -h "$OUT" | cut -f1))"
