"""dis.py EXE va [count] : disassemble"""
import sys, pefile, capstone
pe = pefile.PE(sys.argv[1]); base = pe.OPTIONAL_HEADER.ImageBase
data = pe.get_memory_mapped_image()
va = int(sys.argv[2], 16); n = int(sys.argv[3]) if len(sys.argv) > 3 else 40
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
for i, ins in enumerate(md.disasm(data[va - base: va - base + n * 16], va)):
    if i >= n: break
    print(f"{ins.address:#x}: {ins.mnemonic} {ins.op_str}")
