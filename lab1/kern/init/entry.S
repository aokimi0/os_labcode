    .section .text,"ax",%progbits
    .globl kern_entry
kern_entry:
    lui sp, 0x80210
    j .

.section .data
    .align 12
    .global bootstack
bootstack:
    .space 8192
    .global bootstacktop
bootstacktop: