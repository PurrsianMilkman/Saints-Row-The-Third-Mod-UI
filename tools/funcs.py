"""funcs.py EXE start end : list function starts (after ret+padding) with first calls"""
import sys, pefile, capstone
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
data = pe.get_memory_mapped_image()
a = int(sys.argv[2], 16); b = int(sys.argv[3], 16)
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
starts = [a]
prev = None
for ins in md.disasm(data[a-base:b-base], a):
    if prev and prev.mnemonic in ('ret', 'jmp') and ins.mnemonic not in ('int3', 'nop') and ins.address % 16 == 0:
        starts.append(ins.address)
    if ins.mnemonic not in ('int3', 'nop'): prev = ins
for s in starts:
    calls = []
    for ins in md.disasm(data[s-base:s-base+0x80], s):
        if ins.mnemonic == 'call': calls.append(ins.op_str)
        if ins.mnemonic == 'ret': break
    print(f"{s:#x} calls {' '.join(calls)}")
