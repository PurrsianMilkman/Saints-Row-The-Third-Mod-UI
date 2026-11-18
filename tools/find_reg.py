"""find_reg.py EXE name... : find static luaL_Reg {char*,fn} arrays containing these names; dump each array"""
import sys, pefile, struct, re
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
data = pe.get_memory_mapped_image()
def cstr(va):
    o = va - base
    if not (0 <= o < len(data)): return None
    e = data.find(b'\0', o, o + 64)
    s = data[o:e]
    return s.decode() if e > 0 and re.fullmatch(rb'[A-Za-z_][A-Za-z0-9_]*', s or b'') else None
seen = set()
for name in sys.argv[2:]:
    for m in re.finditer(b'\0' + name.encode() + b'\0', data):
        sva = base + m.start() + 1
        for r in re.finditer(re.escape(struct.pack('<I', sva)), data):
            o = r.start()
            if o % 4: continue
            # walk back to array start
            st = o
            while st >= 8 and cstr(struct.unpack_from('<I', data, st - 8)[0]): st -= 8
            if st in seen: continue
            seen.add(st)
            print(f"## array at {base+st:#x} (hit {name})")
            p = st
            while True:
                n, f = struct.unpack_from('<II', data, p)
                s = cstr(n)
                if not s: break
                print(f"  {s} {f:#x}"); p += 8
