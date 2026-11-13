#!/bin/bash
# Prepare every input that build_spk.sh needs:
#   dl/ame_*.spk          official AME 3.1.0-3005 (x86_64 + aarch64)
#   work/<arch>/          decrypted AME tree, patched libsynoame-license.so, extras
#   build/<arch>/{ffmpeg,ffprobe}   stripped FFmpeg-Builds 9.0 binaries
#   dl/glibc/out_{amd64,arm64}      glibc 2.28 runtime for the bundled loader
#
# Idempotent: everything already present is reused.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"
mkdir -p dl work build out

AME_VER=3.1.0-3005
FF_VER=n9.0
FF_TAG=9.0
GLIBC_VER=2.28-10+deb10u1
GCC_VER=8.3.0-6

SYNO=https://global.synologydownload.com/download/Package/spk/CodecPack/$AME_VER
GH=https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/latest
DEB=http://archive.debian.org/debian/pool/main

fetch() { [ -f "$2" ] || { echo "==> $(basename "$2")"; curl -fsSL -o "$2" "$1"; }; }

# ── 1. AME packages ────────────────────────────────────────────────────
fetch "$SYNO/CodecPack-x86_64-$AME_VER.spk"  dl/ame_x86_64.spk
fetch "$SYNO/CodecPack-rtd1296-$AME_VER.spk" dl/ame_aarch64.spk

# ── 2. FFmpeg-Builds 9.x ───────────────────────────────────────────────
fetch "$GH/ffmpeg-$FF_VER-latest-linux64-gpl-$FF_TAG.tar.xz"    dl/ffmpeg-n9.0-linux64-gpl.tar.xz
fetch "$GH/ffmpeg-$FF_VER-latest-linuxarm64-gpl-$FF_TAG.tar.xz" dl/ffmpeg-n9.0-linuxarm64-gpl.tar.xz

# ── 3. glibc 2.28 runtime ──────────────────────────────────────────────
for a in amd64 arm64; do
    fetch "$DEB/g/glibc/libc6_${GLIBC_VER}_$a.deb" dl/glibc/libc6_${GLIBC_VER}_$a.deb
    fetch "$DEB/g/gcc-8/libgcc1_${GCC_VER}_$a.deb" dl/glibc/libgcc1_${GCC_VER}_$a.deb
done

# ── 4. decrypt + patch the two AME packages ────────────────────────────
PY="python3"
if ! python3 -c 'import pysodium, msgpack' 2>/dev/null; then
    command -v uv >/dev/null || { echo "need python3-pysodium/-msgpack or uv" >&2; exit 1; }
    PY="uv run --quiet --with pysodium --with msgpack python3"
fi

patch_license() {   # <arch> <offsets...> <bytes>
    local arch=$1 offs=$2 bytes=$3
    $PY - "$arch" "$offs" "$bytes" <<'PYEOF'
import sys
from pathlib import Path
arch, offs, patch = sys.argv[1], sys.argv[2], bytes(int(b, 16) for b in sys.argv[3].split())
p = Path(f"work/{arch}/usr/lib/libsynoame-license.so")
d = bytearray(p.read_bytes())
for o in offs.split(","):
    d[int(o, 16):int(o, 16) + len(patch)] = patch
p.write_bytes(d)
PYEOF
}

for arch in x86_64 aarch64; do
    echo "==> AME $arch"
    [ -f "work/$arch/ame.tar" ] || $PY decrypt_spk.py "dl/ame_$arch.spk" "work/$arch/ame.tar"
    if [ ! -d "work/$arch/usr/lib" ]; then
        tar xf "work/$arch/ame.tar" -C "work/$arch" package.tgz
        if [ "$(od -An -tx1 -N6 "work/$arch/package.tgz" | tr -d ' \n')" = "fd377a585a00" ]; then
            tar xJf "work/$arch/package.tgz" -C "work/$arch"
        else
            tar xzf "work/$arch/package.tgz" -C "work/$arch"
        fi
    fi
    tar xf "work/$arch/ame.tar" -C "work/$arch" PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG

    case $arch in
      x86_64)  want_orig=09e3adeafe85b353c9427d93ef0185e9; want_patched=86d5f9f93c80c35e6c59f8ab05da3dc2
               offs=0x9144,0x9234,0x9614,0x9804,0xbe74; bytes="b8 01 00 00 00 c3" ;;
      aarch64) want_orig=f0b33cc2ec241a43f02a332bcbf0d701; want_patched=05ae2e473d9c20d6e3630bb751122305
               offs=0x74c4,0x75f0,0x7a10,0x7c00,0xa220; bytes="20 00 80 52 c0 03 5f d6" ;;
    esac

    got=$(md5sum "work/$arch/usr/lib/libsynoame-license.so" | cut -d' ' -f1)
    if [ "$got" = "$want_orig" ]; then
        patch_license "$arch" "$offs" "$bytes"
        got=$(md5sum "work/$arch/usr/lib/libsynoame-license.so" | cut -d' ' -f1)
    fi
    [ "$got" = "$want_patched" ] || { echo "license patch mismatch for $arch: $got" >&2; exit 1; }
    echo "    libsynoame-license.so patched, md5 $got"
done

# ── 5. strip FFmpeg binaries ───────────────────────────────────────────
mkdir -p build/x86_64 build/aarch64
extract_ff() {  # <dir> <tarball> <strip cmd>
    local dir=$1 tgz=$2 stripcmd=$3
    rm -rf "$dir.srctmp"; mkdir -p "$dir.srctmp"
    tar xJf "$tgz" -C "$dir.srctmp"
    cp "$dir.srctmp"/*/bin/ffmpeg "$dir.srctmp"/*/bin/ffprobe "build/$dir/"
    rm -rf "$dir.srctmp"
    $stripcmd --strip-all "build/$dir/ffmpeg" "build/$dir/ffprobe"
    chmod +x "build/$dir/ffmpeg" "build/$dir/ffprobe"
}
echo "==> stripping ffmpeg binaries"
extract_ff x86_64  dl/ffmpeg-n9.0-linux64-gpl.tar.xz    strip
extract_ff aarch64 dl/ffmpeg-n9.0-linuxarm64-gpl.tar.xz aarch64-linux-gnu-strip

# ── 6. glibc 2.28 libs ─────────────────────────────────────────────────
for pair in "amd64:x86_64-linux-gnu:ld-linux-x86-64.so.2" "arm64:aarch64-linux-gnu:ld-linux-aarch64.so.1"; do
    IFS=: read -r a dir ldsym <<< "$pair"
    O="dl/glibc/out_$a"
    [ -x "$O/$ldsym" ] && continue
    echo "==> glibc $a"
    mkdir -p "$O" "dl/glibc/tmp_$a"
    (cd "dl/glibc/tmp_$a" && ar p "../libc6_${GLIBC_VER}_$a.deb" data.tar.xz | tar xJ)
    (cd "dl/glibc/tmp_$a" && ar p "../libgcc1_${GCC_VER}_$a.deb" data.tar.xz | tar xJ)
    L="dl/glibc/tmp_$a/lib/$dir"
    cp "$L/ld-2.28.so"        "$O/$ldsym"
    cp "$L/libc-2.28.so"      "$O/libc.so.6"
    cp "$L/libm-2.28.so"      "$O/libm.so.6"
    cp "$L/libpthread-2.28.so" "$O/libpthread.so.0"
    cp "$L/libdl-2.28.so"     "$O/libdl.so.2"
    cp "$L/librt-2.28.so"     "$O/librt.so.1"
    [ -f "$L/libmvec-2.28.so" ] && cp "$L/libmvec-2.28.so" "$O/libmvec.so.1"
    cp "$(find "dl/glibc/tmp_$a" -name libgcc_s.so.1 | head -1)" "$O/libgcc_s.so.1"
    rm -rf "dl/glibc/tmp_$a"
done

echo "==> inputs ready"
ls -1 out/ 2>/dev/null || true
