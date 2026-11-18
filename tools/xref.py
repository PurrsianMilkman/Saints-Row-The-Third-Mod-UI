"""xref.py EXE target... : find call/jmp rel32 and push/mov imm32 references to target VAs"""
import sys, pefile, struct
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
data = pe.get_memory_mapped_image()
text = [s for s in pe.sections if s.Name.startswith(b'.text')][0]
t0 = text.VirtualAddress; t1 = t0 + text.Misc_VirtualSize
for t in sys.argv[2:]:
    tv = int(t, 16)
    print("==", t)
    for o in range(t0, t1 - 5):
        op = data[o]
        if op in (0xE8, 0xE9):
            rel, = struct.unpack_from('<i', data, o + 1)
            if base + o + 5 + rel == tv: print(f"  {'call' if op==0xE8 else 'jmp'} at {base+o:#x}")
    imm = struct.pack('<I', tv); i = data.find(imm)
    while i >= 0:
        print(f"  imm at {base+i:#x}"); i = data.find(imm, i + 1)
