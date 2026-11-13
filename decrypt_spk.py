#!/usr/bin/env python3
"""Decrypt a Synology encrypted SPK into a plain tar (synodecrypt-compatible).

Usage: decrypt_spk.py <in.spk> <out.tar>
"""
import os
import struct
import sys
import tarfile
from io import BytesIO

import msgpack
import pysodium

SPK_SIGNING_KEY = bytes.fromhex(
    "FECAA2DD065A86A68E5FE86BA34CD8481590A79FA2C29A7D69F25A3B3BFAA19E")
SPK_MASTER_KEY = bytes.fromhex(
    "CF0D8D6ECB95EF97D0AC6A7021D99124C699808CF2CC5157DFEA5EBF15C805E7")

TAR_BLOCK = 0x200


def main(spk_file, out_tar):
    s = BytesIO(open(spk_file, "rb").read())

    magic = int.from_bytes(s.read(4), "big") & 0xFFFFFF
    assert magic == 0xADBEEF, f"not an encrypted SPK (magic {magic:#x})"

    header_len = int.from_bytes(s.read(4), "little")
    header = s.read(header_len)
    header_sig = s.read(0x40)

    pysodium.crypto_sign_verify_detached(header_sig, header, SPK_SIGNING_KEY)

    mp = msgpack.unpackb(header)
    data, entries_info = mp[0], mp[1]
    ctx = data[0x18:0x18 + 7] + b"\x00"
    subkey_id = int.from_bytes(data[0x10:0x10 + 8], "little")
    kdf_subkey = pysodium.crypto_kdf_derive_from_key(
        0x20, subkey_id, ctx, SPK_MASTER_KEY)

    entries = []
    for entry_len, _checksum in entries_info:
        entries.append((s.tell(), entry_len))
        s.seek(entry_len, os.SEEK_CUR)

    with open(out_tar, "wb") as w:
        for offset, _size in entries:
            s.seek(offset)
            cipher_header = s.read(0x18)
            state = pysodium.crypto_secretstream_xchacha20poly1305_init_pull(
                cipher_header, kdf_subkey)
            dec_hdr, _ = pysodium.crypto_secretstream_xchacha20poly1305_pull(
                state, s.read(0x193), None)
            dec_hdr = dec_hdr.ljust(TAR_BLOCK, b"\x00")
            w.write(dec_hdr)

            tinfo = tarfile.TarInfo.frombuf(dec_hdr, "ascii", "strict")
            size = tinfo.size

            s.seek(offset + TAR_BLOCK)
            cipher_header = s.read(0x18)
            state = pysodium.crypto_secretstream_xchacha20poly1305_init_pull(
                cipher_header, kdf_subkey)

            rem = size
            while rem > 0:
                n = min(0x400000, rem) + 17
                m, _ = pysodium.crypto_secretstream_xchacha20poly1305_pull(
                    state, s.read(n), None)
                w.write(m)
                rem -= len(m)

            pad = TAR_BLOCK - (w.tell() % TAR_BLOCK)
            if pad % TAR_BLOCK:
                w.write(bytes(pad))

        w.write(bytes(TAR_BLOCK * 2))

    print(f"decrypted -> {out_tar}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
