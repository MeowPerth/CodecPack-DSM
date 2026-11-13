#!/bin/bash
# Assemble a CodecPack replacement SPK for DSM 7 from:
#   - FFmpeg-Builds (BtbN) ffmpeg/ffprobe 9.x binaries  (not fully static: needs glibc)
#   - a bundled glibc 2.28 runtime (DSM 7 ships 2.26, the binaries need 2.28)
#   - Synology AME 3.1.0-3005's libsynoame-*.so, with the license checks patched out
#
# Usage: ./build_spk.sh <x86_64|aarch64>
set -euo pipefail

ARCH=${1:?usage: build_spk.sh <x86_64|aarch64>}
ROOT=$(cd "$(dirname "$0")" && pwd)
SRC="$ROOT/src"
BUILD="$ROOT/build/$ARCH"
OUT="$ROOT/out"
PKG_VER="99.0.0-9999"

case "$ARCH" in
  x86_64)
    INFO_ARCH="x86_64"
    SPK_ARCH="x86_64"
    GLIBC_DIR="$ROOT/dl/glibc/out_amd64"
    INTERP="/var/packages/CodecPack/target/pack/lib/glibc/ld-linux-x86-64.so.2"
    ;;
  aarch64)
    INFO_ARCH="rtd1296 rtd1619b armada37xx"
    SPK_ARCH="aarch64"
    GLIBC_DIR="$ROOT/dl/glibc/out_arm64"
    INTERP="/var/packages/CodecPack/target/pack/lib/glibc/ld-linux-aarch64.so.1"
    ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

STAGE="$BUILD/stage"
PKG="$STAGE/package"
WORK="$ROOT/work/$ARCH"

echo "==> staging $ARCH"
rm -rf "$STAGE"
mkdir -p "$PKG"

# 1. package skeleton (scripts, activation files, stubs, etc/settings.conf)
cp -a "$SRC/package/." "$PKG/"
mkdir -p "$PKG/pack/bin" "$PKG/pack/lib/libva" "$PKG/pack/lib/glibc" "$PKG/lib" "$PKG/usr/lib"

# 2. ffmpeg 9.x binaries, re-pointed at the bundled glibc
for b in ffmpeg ffprobe; do
    cp "$ROOT/build/$ARCH/$b" "$PKG/pack/bin/$b.tmp"
    patchelf --force-rpath --set-rpath '$ORIGIN/../lib/glibc' \
             --set-interpreter "$INTERP" "$PKG/pack/bin/$b.tmp"
    if [ "$b" = ffmpeg ]; then mv "$PKG/pack/bin/$b.tmp" "$PKG/pack/bin/ffmpeg41"; else
        mv "$PKG/pack/bin/$b.tmp" "$PKG/pack/bin/ffprobe"; fi
done
cp -a "$GLIBC_DIR/." "$PKG/pack/lib/glibc/"

# 3. symlink layout the DSM apps expect
ln -sf ffmpeg41 "$PKG/pack/bin/ffmpeg33-for-surveillance"
ln -sf ffmpeg41 "$PKG/pack/bin/ffmpeg33-for-audio"
ln -sf ffmpeg41 "$PKG/pack/lib/ffmpeg41-for-synoface"
for f in ffmpeg41 ffprobe ffmpeg33-for-surveillance ffmpeg33-for-audio; do
    ln -sf "../pack/bin/$f" "$PKG/bin/$f"
done
for f in ffmpeg41 ffmpeg33-for-surveillance ffmpeg33-for-audio ffmpeg41-for-synoface libva; do
    ln -sf "../pack/lib/$f" "$PKG/lib/$f"
done

# 4. patched license library + the other AME proprietary libs
cp "$WORK/usr/lib/libsynoame-license.so" "$PKG/usr/lib/"
cp "$WORK"/usr/lib/libsynoame-*.so "$PKG/usr/lib/"
rm -f "$PKG/usr/lib/libsynoame-license.so.bak"

# 5. AME config files
mkdir -p "$PKG/etc/synocrond"
for f in logrotate.conf log_whitelist syslog-ng.conf; do
    cp "$WORK/etc/$f" "$PKG/etc/$f"
done
cp "$WORK/etc/synocrond/CodecPack.conf" "$PKG/etc/synocrond/"

# 6. pack/INFO (what the AME libs read for the "codec pack" version)
sed "s/^arch=.*/arch=\"${INFO_ARCH}\"/" "$SRC/package/pack/INFO" > "$PKG/pack/INFO"

chmod +x "$PKG/pack/bin/ffmpeg41" "$PKG/pack/bin/ffprobe" \
         "$PKG/bin/synocodectool" \
         "$PKG/usr/bin/synoame-bin-check-license" \
         "$PKG/usr/bin/synoame-bin-request-codec"

# 7. package.tgz
echo "==> package.tgz"
tar cJf "$STAGE/package.tgz" -C "$PKG" .
ls -lh "$STAGE/package.tgz"

# 8. SPK envelope
sed "s/^arch=.*/arch=\"${INFO_ARCH}\"/" "$SRC/INFO" > "$STAGE/INFO"
cp "$WORK/PACKAGE_ICON.PNG" "$WORK/PACKAGE_ICON_256.PNG" "$STAGE/"
mkdir -p "$STAGE/scripts" "$STAGE/conf"
cp "$SRC/scripts/"* "$STAGE/scripts/"
cp "$SRC/conf/"* "$STAGE/conf/"
chmod +x "$STAGE/scripts/"*

mkdir -p "$OUT"
SPK="$OUT/CodecPack-${SPK_ARCH}-${PKG_VER}.spk"
(cd "$STAGE" && tar cpf "$SPK" --owner=root --group=root \
    package.tgz INFO PACKAGE_ICON.PNG PACKAGE_ICON_256.PNG scripts conf)
echo "==> built $SPK"
ls -lh "$SPK"
