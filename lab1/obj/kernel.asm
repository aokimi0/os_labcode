
bin/kernel:     file format elf64-littleriscv


Disassembly of section .text:

0000000080200000 <kern_entry>:
    .section .text,"ax",%progbits
    .globl kern_entry
kern_entry:
    lui sp, 0x80210
    80200000:	80210137          	lui	sp,0x80210
    j .
    80200004:	a001                	j	80200004 <kern_entry+0x4>
