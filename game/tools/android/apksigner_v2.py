#!/usr/bin/env python3
"""Підпис APK схемою v2 без Android SDK (для збірки в хмарі, де SDK недоступний).
Підставляється замість build-tools/<ver>/apksigner: розуміє `sign` і `verify` у тому вигляді, як їх викликає Godot.
Потрібні python3-cryptography та сховище ключів PKCS12 (keytool з JDK 9+ створює саме його).
"""
import hashlib
import struct
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import pkcs12

CHUNK = 1024 * 1024
ALGO_RSA_PKCS1_SHA256 = 0x0103
V2_ID = 0x7109871A
MAGIC = b"APK Sig Block 42"


def u32(n):
    return struct.pack("<I", n)


def u64(n):
    return struct.pack("<Q", n)


def lp(b):
    return u32(len(b)) + b


def split_zip(data):
    """(записи, центральний каталог, EOCD) за межею центрального каталогу"""
    eocd = data.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise SystemExit("не ZIP: немає EOCD")
    cd_size, cd_off = struct.unpack("<II", data[eocd + 12:eocd + 20])
    if cd_off + cd_size != eocd:
        raise SystemExit("незвична структура ZIP (вже підписаний або Zip64)")
    return data[:cd_off], data[cd_off:eocd], data[eocd:]


def content_digest(entries, cd, eocd_with_cd_offset):
    digests = []
    for sec in (entries, cd, eocd_with_cd_offset):
        for i in range(0, max(len(sec), 1), CHUNK):
            chunk = sec[i:i + CHUNK]
            digests.append(hashlib.sha256(b"\xa5" + u32(len(chunk)) + chunk).digest())
    return hashlib.sha256(b"\x5a" + u32(len(digests)) + b"".join(digests)).digest()


def sign(src, dst, ks, ks_pass, alias):
    with open(ks, "rb") as f:
        key, cert, _ = pkcs12.load_key_and_certificates(f.read(), ks_pass.encode())
    if key is None:
        raise SystemExit("у сховищі немає ключа (потрібен PKCS12)")
    data = open(src, "rb").read()
    entries, cd, eocd = split_zip(data)
    # У дайджесті поле зміщення КК вказує на початок блоку підпису, тобто старе зміщення
    digest = content_digest(entries, cd, eocd)
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    pub_der = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    digest_rec = lp(u32(ALGO_RSA_PKCS1_SHA256) + lp(digest))
    signed_data = lp(digest_rec) + lp(lp(cert_der)) + lp(b"")
    sig = key.sign(signed_data, padding.PKCS1v15(), hashes.SHA256())
    sig_rec = lp(u32(ALGO_RSA_PKCS1_SHA256) + lp(sig))
    signer = lp(signed_data) + lp(sig_rec) + lp(pub_der)
    value = lp(lp(signer))
    pair = u64(4 + len(value)) + u32(V2_ID) + value
    size = len(pair) + 8 + len(MAGIC)
    block = u64(size) + pair + u64(size) + MAGIC
    new_off = len(entries) + len(block)
    eocd_new = eocd[:16] + u32(new_off) + eocd[20:]
    with open(dst, "wb") as f:
        f.write(entries + block + cd + eocd_new)
    print("signed (v2):", dst)


def verify(path):
    data = open(path, "rb").read()
    eocd = data.rfind(b"PK\x05\x06")
    cd_off = struct.unpack("<I", data[eocd + 16:eocd + 20])[0]
    if data[cd_off - 16:cd_off] != MAGIC:
        raise SystemExit("DOES NOT VERIFY: немає блоку підпису v2")
    size = struct.unpack("<Q", data[cd_off - 24:cd_off - 16])[0]
    start = cd_off - size - 8
    block = data[start + 8:cd_off - 24]
    # єдина пара (ID 0x7109871a)
    plen, pid = struct.unpack("<QI", block[:12])
    if pid != V2_ID:
        raise SystemExit("DOES NOT VERIFY: незнайомий блок")
    v = block[12:8 + plen]
    signer = v[8:]   # пропускаємо довжини послідовності підписантів і підписанта
    sd_len = struct.unpack("<I", signer[:4])[0]
    signed_data = signer[4:4 + sd_len]
    rest = signer[4 + sd_len:]
    sigs_len = struct.unpack("<I", rest[:4])[0]
    sig_rec = rest[4:4 + sigs_len]
    sl = struct.unpack("<I", sig_rec[8:12])[0]   # довжина запису, алгоритм, довжина підпису
    sig = sig_rec[12:12 + sl]
    pk_len = struct.unpack("<I", rest[4 + sigs_len:8 + sigs_len])[0]
    pub = serialization.load_der_public_key(rest[8 + sigs_len:8 + sigs_len + pk_len])
    pub.verify(sig, signed_data, padding.PKCS1v15(), hashes.SHA256())
    dig = signed_data[4 + 4 + 4 + 4:4 + 4 + 4 + 4 + 32]
    entries = data[:start]
    cdsec = data[cd_off:eocd]
    eocd_old = data[eocd:eocd + 16] + u32(start) + data[eocd + 20:]
    if content_digest(entries, cdsec, eocd_old) != dig:
        raise SystemExit("DOES NOT VERIFY: дайджест не збігається")
    print("Verifies (v2)")


def main(argv):
    if len(argv) < 2:
        raise SystemExit("usage: apksigner sign|verify ...")
    cmd, args = argv[1], argv[2:]
    if cmd == "--version":
        print("0.9-amber")   # Godot лише перевіряє, що інструмент запускається
        return
    if cmd == "verify":
        verify([a for a in args if not a.startswith("--")][-1])
        return
    if cmd != "sign":
        raise SystemExit("непідтримувана команда " + cmd)
    opt, pos, i = {}, [], 0
    while i < len(args):
        a = args[i]
        if a in ("--ks", "--ks-pass", "--ks-key-alias", "--out", "--key-pass", "--min-sdk-version", "--max-sdk-version"):
            opt[a] = args[i + 1]
            i += 2
        elif a.startswith("--"):
            i += 1
        else:
            pos.append(a)
            i += 1
    pw = opt["--ks-pass"]
    pw = pw.split(":", 1)[1] if pw.startswith("pass:") else pw
    src = pos[-1]
    sign(src, opt.get("--out", src), opt["--ks"], pw, opt.get("--ks-key-alias", ""))


if __name__ == "__main__":
    main(sys.argv)
