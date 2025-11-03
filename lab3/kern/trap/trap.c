/*
 * @file
 * @brief RISC-V 监管态陷阱（中断/异常）处理模块。
 *
 * 提供异常入口初始化、陷阱分发、中断与异常的具体处理逻辑：
 * - 时钟中断：每 100 次触发打印一次“100 ticks”，累计 10 次后通过 SBI 关机。
 * - 非法指令/断点异常：输出异常类型与触发地址，并将 tf->epc 前移 4 字节跳过故障指令。
 */
#include <clock.h>
#include <console.h>
#include <defs.h>
#include <assert.h>
#include <kdebug.h>
#include <memlayout.h>
#include <mmu.h>
#include <riscv.h>
#include <stdio.h>
#include <trap.h>
#include <sbi.h>

#define TICK_NUM 100

/**
 * @brief 打印 TICK_NUM 次时钟中断提示信息。
 *
 * 当计数达到 TICK_NUM 时被调用，输出一行“100 ticks”。在 DEBUG_GRADE 模式下，
 * 还会输出测试结束信息并触发 panic 以便评分脚本检测。
 */
static void print_ticks() {
    cprintf("%d ticks\n", TICK_NUM);
    cprintf("End of Test.\n");
#ifdef DEBUG_GRADE
    panic("EOT: kernel seems ok.");
#endif
}

/**
 * @brief 初始化异常向量入口。
 *
 * 设置 `sscratch=0` 表示当前处于内核上下文；将异常向量寄存器 `stvec` 指向
 * 汇编入口 `__alltraps`，后续所有 trap 将先进入统一入口完成保存上下文。
 */
void idt_init(void) {
    /* LAB3 YOUR CODE : STEP 2 */
    /* (1) Where are the entry addrs of each Interrupt Service Routine (ISR)?
     *     All ISR's entry addrs are stored in __vectors. where is uintptr_t
     * __vectors[] ?
     *     __vectors[] is in kern/trap/vector.S which is produced by
     * tools/vector.c
     *     (try "make" command in lab3, then you will find vector.S in kern/trap
     * DIR)
     *     You can use  "extern uintptr_t __vectors[];" to define this extern
     * variable which will be used later.
     * (2) Now you should setup the entries of ISR in Interrupt Description
     * Table (IDT).
     *     Can you see idt[256] in this file? Yes, it's IDT! you can use SETGATE
     * macro to setup each item of IDT
     * (3) After setup the contents of IDT, you will let CPU know where is the
     * IDT by using 'lidt' instruction.
     *     You don't know the meaning of this instruction? just google it! and
     * check the libs/x86.h to know more.
     *     Notice: the argument of lidt is idt_pd. try to find it!
     */
    extern void __alltraps(void);
    /* Set sup0 scratch register to 0, indicating to exception vector
       that we are presently executing in the kernel */
    write_csr(sscratch, 0);
    /* Set the exception vector address */
    write_csr(stvec, &__alltraps);
}

/**
 * @brief 判断陷阱是否发生在内核态。
 * @param tf 陷阱现场（寄存器上下文）。
 * @return true 表示在内核态（`SSTATUS_SPP` 置位），false 表示在用户态。
 */
bool trap_in_kernel(struct trapframe *tf) {
    return (tf->status & SSTATUS_SPP) != 0;
}

/**
 * @brief 打印陷阱现场信息。
 * @param tf 陷阱现场（寄存器上下文）。
 */
void print_trapframe(struct trapframe *tf) {
    cprintf("trapframe at %p\n", tf);
    print_regs(&tf->gpr);
    cprintf("  status   0x%08x\n", tf->status);
    cprintf("  epc      0x%08x\n", tf->epc);
    cprintf("  badvaddr 0x%08x\n", tf->badvaddr);
    cprintf("  cause    0x%08x\n", tf->cause);
}

/**
 * @brief 打印通用寄存器组内容。
 * @param gpr 通用寄存器快照。
 */
void print_regs(struct pushregs *gpr) {
    cprintf("  zero     0x%08x\n", gpr->zero);
    cprintf("  ra       0x%08x\n", gpr->ra);
    cprintf("  sp       0x%08x\n", gpr->sp);
    cprintf("  gp       0x%08x\n", gpr->gp);
    cprintf("  tp       0x%08x\n", gpr->tp);
    cprintf("  t0       0x%08x\n", gpr->t0);
    cprintf("  t1       0x%08x\n", gpr->t1);
    cprintf("  t2       0x%08x\n", gpr->t2);
    cprintf("  s0       0x%08x\n", gpr->s0);
    cprintf("  s1       0x%08x\n", gpr->s1);
    cprintf("  a0       0x%08x\n", gpr->a0);
    cprintf("  a1       0x%08x\n", gpr->a1);
    cprintf("  a2       0x%08x\n", gpr->a2);
    cprintf("  a3       0x%08x\n", gpr->a3);
    cprintf("  a4       0x%08x\n", gpr->a4);
    cprintf("  a5       0x%08x\n", gpr->a5);
    cprintf("  a6       0x%08x\n", gpr->a6);
    cprintf("  a7       0x%08x\n", gpr->a7);
    cprintf("  s2       0x%08x\n", gpr->s2);
    cprintf("  s3       0x%08x\n", gpr->s3);
    cprintf("  s4       0x%08x\n", gpr->s4);
    cprintf("  s5       0x%08x\n", gpr->s5);
    cprintf("  s6       0x%08x\n", gpr->s6);
    cprintf("  s7       0x%08x\n", gpr->s7);
    cprintf("  s8       0x%08x\n", gpr->s8);
    cprintf("  s9       0x%08x\n", gpr->s9);
    cprintf("  s10      0x%08x\n", gpr->s10);
    cprintf("  s11      0x%08x\n", gpr->s11);
    cprintf("  t3       0x%08x\n", gpr->t3);
    cprintf("  t4       0x%08x\n", gpr->t4);
    cprintf("  t5       0x%08x\n", gpr->t5);
    cprintf("  t6       0x%08x\n", gpr->t6);
}

/**
 * @brief 中断分发处理函数。
 *
 * 依据 `tf->cause` 的最高位（符号位）区分中断来源并分发。
 * 其中对 `IRQ_S_TIMER`：
 * - 先调用 `clock_set_next_event` 安排下一次时钟中断；
 * - 增加全局 `ticks`；
 * - 每 `TICK_NUM` 次打印一次“100 ticks”；
 * - 打印达到 10 次后，调用 `sbi_shutdown` 关机。
 *
 * @param tf 陷阱现场（寄存器上下文）。
 */
void interrupt_handler(struct trapframe *tf) {
    intptr_t cause = (tf->cause << 1) >> 1;
    switch (cause) {
        case IRQ_U_SOFT:
            cprintf("User software interrupt\n");
            break;
        case IRQ_S_SOFT:
            cprintf("Supervisor software interrupt\n");
            break;
        case IRQ_H_SOFT:
            cprintf("Hypervisor software interrupt\n");
            break;
        case IRQ_M_SOFT:
            cprintf("Machine software interrupt\n");
            break;
        case IRQ_U_TIMER:
            cprintf("User Timer interrupt\n");
            break;
        case IRQ_S_TIMER:
            // "All bits besides SSIP and USIP in the sip register are
            // read-only." -- privileged spec1.9.1, 4.1.4, p59
            // In fact, Call sbi_set_timer will clear STIP, or you can clear it
            // directly.
            // cprintf("Supervisor timer interrupt\n");
            /* LAB3 EXERCISE1   YOUR CODE :  */
            /*(1)设置下次时钟中断- clock_set_next_event()
             *(2)计数器（ticks）加一
             *(3)当计数器加到100的时候，我们会输出一个`100ticks`表示我们触发了100次时钟中断，同时打印次数（num）加一
            * (4)判断打印次数，当打印次数为10时，调用<sbi.h>中的关机函数关机
            */
            clock_set_next_event();
            static size_t printed_times = 0;
            if (++ticks % TICK_NUM == 0) {
                print_ticks();
                if (++printed_times >= 10) {
                    sbi_shutdown();
                }
            }
            break;
        case IRQ_H_TIMER:
            cprintf("Hypervisor software interrupt\n");
            break;
        case IRQ_M_TIMER:
            cprintf("Machine software interrupt\n");
            break;
        case IRQ_U_EXT:
            cprintf("User software interrupt\n");
            break;
        case IRQ_S_EXT:
            cprintf("Supervisor external interrupt\n");
            break;
        case IRQ_H_EXT:
            cprintf("Hypervisor software interrupt\n");
            break;
        case IRQ_M_EXT:
            cprintf("Machine software interrupt\n");
            break;
        default:
            print_trapframe(tf);
            break;
    }
}

/**
 * @brief 异常分发处理函数。
 *
 * 当前实现对两类同步异常给出示例处理：
 * - 非法指令（CAUSE_ILLEGAL_INSTRUCTION）：打印异常类型与触发地址，并将 `tf->epc += 4`
 *   跳过导致异常的指令，避免重复陷阱。
 * - 断点（CAUSE_BREAKPOINT）：同样打印信息，并推进 `tf->epc` 跳过断点指令。
 * 其他异常保持占位，后续按实验需要完善。
 *
 * @param tf 陷阱现场（寄存器上下文）。
 */
void exception_handler(struct trapframe *tf) {
    switch (tf->cause) {
        case CAUSE_MISALIGNED_FETCH:
            break;
        case CAUSE_FAULT_FETCH:
            break;
        case CAUSE_ILLEGAL_INSTRUCTION:
            // 非法指令异常处理
            /* LAB3 CHALLENGE3   YOUR CODE :  */
            /*(1)输出指令异常类型（ Illegal instruction）
             *(2)输出异常指令地址
             *(3)更新 tf->epc寄存器
            */
            cprintf("Illegal instruction caught at 0x%08x\n", tf->epc);
            cprintf("Exception type:Illegal instruction\n");
            tf->epc += 4;
            break;
        case CAUSE_BREAKPOINT:
            // 断点异常处理
            /* LAB3 CHALLLENGE3   YOUR CODE :  */
            /*(1)输出指令异常类型（ breakpoint）
             *(2)输出异常指令地址
             *(3)更新 tf->epc寄存器
            */
            cprintf("ebreak caught at 0x%08x\n", tf->epc);
            cprintf("Exception type: breakpoint\n");
            tf->epc += 4;
            break;
        case CAUSE_MISALIGNED_LOAD:
            break;
        case CAUSE_FAULT_LOAD:
            break;
        case CAUSE_MISALIGNED_STORE:
            break;
        case CAUSE_FAULT_STORE:
            break;
        case CAUSE_USER_ECALL:
            break;
        case CAUSE_SUPERVISOR_ECALL:
            break;
        case CAUSE_HYPERVISOR_ECALL:
            break;
        case CAUSE_MACHINE_ECALL:
            break;
        default:
            print_trapframe(tf);
            break;
    }
}

/**
 * @brief 统一陷阱分发逻辑。
 *
 * `tf->cause` 为有符号数，最高位为 1 表示外部中断，为 0 表示同步异常。
 * 依据该位选择调用 `interrupt_handler` 或 `exception_handler`。
 *
 * @param tf 陷阱现场（寄存器上下文）。
 */
static inline void trap_dispatch(struct trapframe *tf) {
    if ((intptr_t)tf->cause < 0) {
        // interrupts
        interrupt_handler(tf);
    } else {
        // exceptions
        exception_handler(tf);
    }
}

/**
 * @brief C 侧陷阱入口：处理中断/异常。
 *
 * 汇编入口 `__alltraps` 完成保存现场后，调用此函数。该函数仅做分发，返回后
 * 汇编通过 `RESTORE_ALL` 恢复现场并执行 `sret` 返回原执行流。
 *
 * @param tf 陷阱现场（寄存器上下文）。
 */
void trap(struct trapframe *tf) {
    // dispatch based on what type of trap occurred
    trap_dispatch(tf);
}
