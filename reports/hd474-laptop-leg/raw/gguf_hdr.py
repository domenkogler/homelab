"""Read GGUF metadata KV pairs with a byte-accurate reader.

Prints the first N pairs with their raw type code so a wrong type table is visible
immediately instead of showing up as a MemoryError 40 keys in.
"""
import binascii
import json
import os
import struct
import sys

SIMPLE = {0: "<B", 1: "<b", 2: "<H", 3: "<h", 4: "<I", 5: "<i", 6: "<f", 7: "<?",
          10: "<Q", 11: "<q", 12: "<d"}


def rd(f, t, trace=None):
    if t in SIMPLE:
        fmt = SIMPLE[t]
        return struct.unpack(fmt, f.read(struct.calcsize(fmt)))[0]
    if t == 8:                                    # string: u64 length + utf8
        (L,) = struct.unpack("<Q", f.read(8))
        if L > 1 << 24:
            raise AssertionError("implausible string length %d at %d" % (L, f.tell()))
        return f.read(L).decode("utf-8", "replace")
    if t == 9:                                    # array: elem_type(u32) + count(u64) + elems
        # FIXED 2026-09-30: the element type is a uint32, NOT a uint8 (GGUF v3 spec). Reading one
        # byte here desynced the stream by 3 and made the reader stop at the first array key -
        # which is why `general.architecture`'s block looked fine but the Qwen-VL header printed
        # an empty metadata set. Symptom to remember: "implausible string length" inside an array.
        (it,) = struct.unpack("<I", f.read(4))
        (c,) = struct.unpack("<Q", f.read(8))
        if c > 1 << 20:
            raise AssertionError("implausible array count %d at %d" % (c, f.tell()))
        return [rd(f, it) for _ in range(c)]
    raise AssertionError("unknown type %r at %d" % (t, f.tell()))


def _str(f, wide=True):
    (L,) = struct.unpack("<Q" if wide else "<I", f.read(8 if wide else 4))
    if L > 1 << 24:
        raise AssertionError("implausible string length %d at %d" % (L, f.tell()))
    return f.read(L).decode("utf-8", "replace")


def header(path, trace=0):
    out = {}
    with open(path, "rb") as f:
        if f.read(4) != b"GGUF":
            return {"_error": "not GGUF"}
        (ver,) = struct.unpack("<I", f.read(4))
        (nt, nkv) = struct.unpack("<QQ", f.read(16))
        # Verify the string encoding empirically instead of trusting the spec: GGUF v3
        # should use u64 lengths, but a u32 variant would silently desync every offset by 4.
        wide = True
        probe = f.tell()
        if _str(f, True) != "general.architecture":
            f.seek(probe)
            if _str(f, False) != "general.architecture":
                raise AssertionError("cannot read first key - layout unknown")
            wide = False
        f.seek(probe)
        for i in range(nkv):
            key = _str(f, wide)
            # GGUF type codes are uint32, NOT uint64: reading 8 bytes here eats the low
            # half of the following string length and desyncs every later offset.
            (t,) = struct.unpack("<I", f.read(4))
            if t > 12:
                raise AssertionError("key #%d %r type %d at %d" % (i, key[:30], t, f.tell()))
            try:
                if t == 8:
                    val = _str(f, wide)
                elif t == 9:
                    # elem_type is uint32 (see rd() above): a uint8 read here desyncs every offset.
                    (it,) = struct.unpack("<I", f.read(4))
                    (c,) = struct.unpack("<Q", f.read(8))
                    val = [_str(f, wide) if it == 8 else struct.unpack(SIMPLE[it], f.read(struct.calcsize(SIMPLE[it])))[0] for _ in range(c)]
                else:
                    fmt = SIMPLE[t]
                    val = struct.unpack(fmt, f.read(struct.calcsize(fmt)))[0]
            except Exception as e:                    # tokenizer blobs are not needed for KV math;
                out["_parse_stopped_at"] = key       # stop cleanly and keep what we have
                print("  (parse stopped at %r: %s)" % (key, e))
                break
            if trace:
                print("  [%2d] type=%-3d %-46s = %s" % (i, t, key[:46], str(val)[:60]))
            out[key] = val
        out["_version"] = ver
        out["_tensors"] = nt
        out["_nkv"] = nkv
        out["_wide"] = wide
    return out


if __name__ == "__main__":
    paths = sys.argv[1:] or [
        r"D:/llm/models/unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF/"
        "Qwen3-VL-30B-A3B-Instruct-UD-Q4_K_XL.gguf"]
    for p in paths:
        print("==", os.path.basename(p), "%.2f GB" % (os.path.getsize(p) / 1e9))
        d = header(p, trace=0)
        if "_error" in d:
            print("  ", d)
            continue
        arch = d.get("general.architecture", "?")
        print("  arch=%s tensors=%s nkv=%s" % (arch, d.get("_tensors"), d.get("_nkv")))
        KEEP = ("context_length", "head_count", "block_count", "sliding", "attention.type",
                "key_length", "value_length", "quantization", "expert", "feed_forward",
                "rope_type", "hidden_size", "vae", "is_unique", "sampling", "vision",
                "image_min_pixels", "image_max_pixels", "patch_size", "merge_size")
        meta = {k: v for k, v in d.items() if any(s in k.lower() for s in KEEP)}
        print(json.dumps(meta, indent=1, default=str))
        if d.get("_parse_stopped_at"):
            print("  !! header parse stopped early at %r - the numbers above are TRUNCATED, not the"
                  " whole file" % d["_parse_stopped_at"])
