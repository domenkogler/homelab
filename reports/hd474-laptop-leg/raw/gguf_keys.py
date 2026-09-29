"""Pull named int/float/string metadata out of a GGUF header without parsing the whole KV table.

The Qwen-VL GGUF encodes array-of-string values in a way that desyncs a sequential reader at
general.tags, and the architecture keys we care about (block_count, head_count_kv, key_length,
context_length) live AFTER that. Keys appear verbatim in the header, so locate the key bytes and
decode the value that follows: type is uint32, then the payload.
"""
import json
import struct
import sys

HEAD = 1 << 20          # metadata always lives in the first megabyte
TYPES = {0: ("<B", 1), 1: ("<b", 1), 2: ("<H", 2), 3: ("<h", 2), 4: ("<I", 4), 5: ("<i", 4),
         6: ("<f", 4), 7: ("<?", 1), 10: ("<Q", 8), 11: ("<q", 8), 12: ("<d", 8)}


def scan(path, keys, blob=HEAD):
    with open(path, "rb") as f:
        buf = f.read(blob)
    out = {}
    for k in keys:
        kb = k.encode()
        i = buf.find(kb)
        if i < 0:
            continue
        p = i + len(kb)                       # key bytes, then uint32 type, then payload
        (t,) = struct.unpack("<I", buf[p:p + 4])
        p += 4
        if t == 8:                            # string
            (L,) = struct.unpack("<Q", buf[p:p + 8])
            out[k] = buf[p + 8:p + 8 + L].decode("utf-8", "replace")
        elif t == 9:                          # array: elem type + count
            it = buf[p]
            (c,) = struct.unpack("<Q", buf[p + 1:p + 9])
            q = p + 9
            fmt, sz = TYPES[it]
            out[k] = [struct.unpack(fmt, buf[q + n * sz:q + n * sz + sz])[0] for n in range(min(c, 8))]
            if c > 8:
                out[k].append("...(+%d)" % (c - 8))
        elif t in TYPES:
            fmt, sz = TYPES[t]
            out[k] = struct.unpack(fmt, buf[p:p + sz])[0]
        else:
            out[k] = "type %d unsupported" % t
    return out


if __name__ == "__main__":
    arch = sys.argv[2] if len(sys.argv) > 2 else "qwen3vlmoe"
    keys = ["%s.%s" % (arch, s) for s in (
        "block_count", "attention.head_count", "attention.head_count_kv",
        "attention.key_length", "attention.value_length", "attention.type",
        "attention.sliding_window", "context_length", "feed_forward_length",
        "rope.freq_base", "expert_count", "expert_used_count")]
    keys += ["general.architecture", "general.quantization_version"]
    print(json.dumps(scan(sys.argv[1], keys), indent=1, default=str))
