"""scan_bindings.py EXE : list Lua binding registrations (mov [esp+X],name ; mov [esp+X+4],fn) -> name fn_imm_addr fn"""
import sys, pefile, re, struct
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
data = pe.get_memory_mapped_image()
def cstr(va):
    o = va - base
    if o < 0 or o >= len(data): return None
    e = data.find(b'\0', o, o + 80)
    s = data[o:e]
    if e < 0 or len(s) < 2 or not re.fullmatch(rb'[A-Za-z_][A-Za-z0-9_]*', s): return None
    return s.decode()
text = [s for s in pe.sections if s.Name.startswith(b'.text')][0]
t0 = text.VirtualAddress; t1 = t0 + text.Misc_VirtualSize
out = []
for m in re.finditer(rb'\xC7\x84\x24(....)(....)\xC7\x84\x24(....)(....)', data[t0:t1], re.S):
    d1, n, d2, f = struct.unpack('<iIiI', m.group(1) + m.group(2) + m.group(3) + m.group(4))
    if d2 != d1 + 4: continue
    s = cstr(n)
    if s and t0 + base <= f < t1 + base:
        out.append((s, base + t0 + m.start() + 18, f))
for m in re.finditer(rb'\xC7\x44\x24(.)(....)\xC7\x44\x24(.)(....)', data[t0:t1], re.S):
    d1 = m.group(1)[0]; d2 = m.group(3)[0]
    n, = struct.unpack('<I', m.group(2)); f, = struct.unpack('<I', m.group(4))
    if d2 != (d1 + 4) & 0xff: continue
    s = cstr(n)
    if s and t0 + base <= f < t1 + base:
        out.append((s, base + t0 + m.start() + 12, f))
for s, imm, f in out: print(f"{s} {imm:#x} {f:#x}")
