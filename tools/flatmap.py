#!/usr/bin/env python3
"""flatmap.py -- produce a FLAT-MAPPED image of a PE (file offset == RVA).

Every other patch-day tool (patch_day.py, secret_gates.py, the capstone
re-derivation scripts) expects a dump where reading at offset X gives the bytes
that live at RVA X. That is exactly the PE loader's view: each section written at
its VirtualAddress, padded to SizeOfImage.

    python tools/flatmap.py <input.exe> <output_flat.exe>

No running process needed -- this is a pure offline transform of the on-disk PE.
"""
import sys, struct, os


def flatmap(src_path, dst_path):
    data = open(src_path, "rb").read()
    if data[:2] != b"MZ":
        raise SystemExit("not a PE (no MZ)")
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    if data[e_lfanew:e_lfanew + 4] != b"PE\0\0":
        raise SystemExit("not a PE (no PE signature)")

    coff = e_lfanew + 4
    num_sections = struct.unpack_from("<H", data, coff + 2)[0]
    size_opt = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    pe32plus = (magic == 0x20B)

    # SizeOfImage sits at the same offset in both PE32 and PE32+
    size_of_image = struct.unpack_from("<I", data, opt + 56)[0]
    size_of_headers = struct.unpack_from("<I", data, opt + 60)[0]
    image_base = (struct.unpack_from("<Q", data, opt + 24)[0] if pe32plus
                  else struct.unpack_from("<I", data, opt + 28)[0])

    out = bytearray(size_of_image)
    # headers first
    out[0:size_of_headers] = data[0:size_of_headers]

    sec = opt + size_opt
    print(f"  PE32+={pe32plus}  ImageBase=0x{image_base:X}  SizeOfImage={size_of_image:,} "
          f"({size_of_image/1024/1024:.1f} MB)  sections={num_sections}")
    for i in range(num_sections):
        off = sec + i * 40
        name = data[off:off + 8].rstrip(b"\0").decode(errors="replace")
        vsize = struct.unpack_from("<I", data, off + 8)[0]
        vaddr = struct.unpack_from("<I", data, off + 12)[0]
        rawsz = struct.unpack_from("<I", data, off + 16)[0]
        rawptr = struct.unpack_from("<I", data, off + 20)[0]
        chars = struct.unpack_from("<I", data, off + 36)[0]
        n = min(rawsz, vsize) if vsize else rawsz
        if rawptr and n:
            chunk = data[rawptr:rawptr + n]
            end = vaddr + len(chunk)
            if end <= size_of_image:
                out[vaddr:end] = chunk
            else:
                print(f"    !! {name} overflows SizeOfImage, truncating")
                out[vaddr:size_of_image] = chunk[:size_of_image - vaddr]
        perm = "".join(c for c, b in (("R", 0x40000000), ("W", 0x80000000), ("X", 0x20000000)) if chars & b)
        print(f"    {name:8} VA=0x{vaddr:08X} VSize=0x{vsize:08X} Raw=0x{rawsz:08X} {perm}")

    open(dst_path, "wb").write(bytes(out))
    print(f"  wrote {dst_path} ({os.path.getsize(dst_path):,} bytes)")
    return image_base


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    print(f"flat-mapping {sys.argv[1]}")
    base = flatmap(sys.argv[1], sys.argv[2])
    print(f"  -> file offset == RVA. runtime ImageBase would be 0x{base:X}")
