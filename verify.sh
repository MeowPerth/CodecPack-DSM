#!/bin/sh
# Run on the NAS after installing CodecPack-*.spk:
#   sudo sh verify.sh
# Checks that the replacement ffmpeg is reachable, is a real HEVC-capable
# FFmpeg 9.x, and that the codec pack reports itself installed.

PKG=/var/packages/CodecPack/target
fail=0

check() { printf '%-52s %s\n' "$1" "$2"; }

check "package dir" "$([ -d "$PKG" ] && echo OK || { echo MISSING; fail=1; })"
check "bin/ffmpeg41" "$([ -x "$PKG/bin/ffmpeg41" ] && echo OK || { echo MISSING; fail=1; })"
check "pack_status.conf" "$(cat /var/packages/CodecPack/var/pack_status.conf 2>/dev/null || echo 'no status file')"

if [ -x "$PKG/bin/ffmpeg41" ]; then
    ver=$("$PKG/bin/ffmpeg41" -hide_banner -version 2>/dev/null | head -1)
    check "ffmpeg -version" "${ver:-FAILED TO RUN}"
    [ -n "$ver" ] || fail=1
    hevc=$("$PKG/bin/ffmpeg41" -hide_banner -encoders 2>/dev/null | grep -c 'libx265')
    check "libx265 encoder" "$([ "$hevc" -ge 1 ] && echo OK || { echo MISSING; fail=1; })"
    h264=$("$PKG/bin/ffmpeg41" -hide_banner -encoders 2>/dev/null | grep -c 'libx264')
    check "libx264 encoder" "$([ "$h264" -ge 1 ] && echo OK || { echo MISSING; fail=1; })"
    echo "--- 2-second HEVC encode smoke test"
    if "$PKG/bin/ffmpeg41" -hide_banner -loglevel error -f lavfi -i testsrc2=size=1280x720:rate=25 \
        -t 2 -c:v libx265 -x265-params log-level=error -f null - 2>/tmp/hevc_test.err; then
        echo "    HEVC encode: OK"
    else
        echo "    HEVC encode: FAILED"; sed 's/^/    /' /tmp/hevc_test.err; fail=1
    fi
fi

echo
echo "recent CodecPack log lines:"
tail -n 5 /var/log/packages/CodecPack.log 2>/dev/null || echo "  (no log)"

exit $fail
