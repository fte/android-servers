#!/usr/bin/env python3
# Walk ELF DT_NEEDED deps of /system/bin executables and report any library
# that is missing from the pulled system trees (lib, vendor-lib).
import os, re, struct, sys

# This script lives in scripts/; the pulled /system tree belongs at <repo>/syspull
# (not versioned: it is a local `adb pull /system syspull` copy).
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PULLED = os.path.join(ROOT, "syspull")
SEARCH = [
    os.path.join(PULLED, "lib"),
    os.path.join(PULLED, "vendor-lib"),
]

def read_needed(path):
    """Return list of DT_NEEDED names for a 32-bit little-endian ELF."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    if len(data) < 52 or data[:4] != b"\x7fELF":
        return None
    if data[4] != 1 or data[5] != 1:  # not ELFCLASS32 / little-endian
        return None
    e_shoff, = struct.unpack_from("<I", data, 0x20)
    e_shentsize, e_shnum = struct.unpack_from("<HH", data, 0x2E)
    if not e_shoff or not e_shnum:
        return None
    # locate .dynamic section (type SHT_DYNAMIC = 6) and .dynstr (SHT_STRTAB = 3)
    dyn = None
    strtab_off = strtab_sz = None
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_type, = struct.unpack_from("<I", data, off + 0x04)
        sh_offset, = struct.unpack_from("<I", data, off + 0x10)
        sh_size, = struct.unpack_from("<I", data, off + 0x14)
        sh_link, = struct.unpack_from("<I", data, off + 0x18)
        if sh_type == 6:
            dyn = (sh_offset, sh_size)
        if sh_type == 3 and dyn is not None and strtab_off is None:
            pass
    # second pass for strtab linked to the dynamic section
    dyn_off, dyn_size = dyn if dyn else (None, None)
    if dyn_off is None:
        return []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_type, = struct.unpack_from("<I", data, off + 0x04)
        sh_offset, = struct.unpack_from("<I", data, off + 0x10)
        sh_size, = struct.unpack_from("<I", data, off + 0x14)
        if sh_type == 3:  # .dynstr
            strtab_off, strtab_sz = sh_offset, sh_size
            break
    if strtab_off is None:
        return []
    needed = []
    DT_NEEDED = 1
    for pos in range(dyn_off, dyn_off + dyn_size, 8):
        d_tag, d_val = struct.unpack_from("<iI", data, pos)
        if d_tag == 0:
            break
        if d_tag == DT_NEEDED:
            end = data.find(b"\x00", strtab_off + d_val)
            name = data[strtab_off + d_val:end]
            needed.append(name.decode("utf-8", "replace"))
    return needed

def main():
    available = set()
    for d in SEARCH:
        if os.path.isdir(d):
            available.update(os.listdir(d))
    bins = os.path.join(PULLED, "bin")
    missing = set()          # name -> requirers
    requirers = {}
    broken = set()
    def visit(name, chain):
        path = None
        for d in SEARCH:
            p = os.path.join(d, name)
            if os.path.exists(p):
                path = p
                break
        if path is None:
            missing.add(name)
            requirers.setdefault(name, set()).update(chain[-1:])
            return
        if name in broken:
            return
        deps = read_needed(path)
        if deps is None:
            broken.add(name)
            return
        for dep in deps:
            if dep not in available:
                missing.add(dep)
                requirers.setdefault(dep, set()).update(chain[-1:])
            else:
                visit(dep, chain + [dep])
    for exe in sorted(os.listdir(bins)):
        exe_path = os.path.join(bins, exe)
        if not os.path.isfile(exe_path):
            continue
        deps = read_needed(exe_path)
        if deps is None:
            continue  # shell script, cert, non-ELF
        for dep in deps:
            if dep not in available:
                missing.add(dep)
                requirers.setdefault(dep, set()).add(exe)
            else:
                visit(dep, [exe, dep])
    if missing:
        print("MISSING LIBS:")
        for m in sorted(missing):
            print("  %-45s needed by: %s" % (m, ", ".join(sorted(requirers[m]))))
    else:
        print("NO MISSING LIBS")
    if broken:
        print("UNREADABLE (not parsed):", ", ".join(sorted(broken)))

if __name__ == "__main__":
    main()
