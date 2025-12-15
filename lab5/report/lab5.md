# Lab 5 实验报告

## 练习 1: 加载应用程序并执行（需要编码）

### 1\. 设计与实现 `load_icode` 第 6 步（trapframe 初始化）

- **整体思路**：在前面几步完成用户地址空间建立（为各个 `ELF` 段建立 `vma`、分配物理页并拷贝代码/数据、建立 BSS、创建用户栈）以及切换到新的用户页表之后，通过设置当前进程 `proc_struct` 中的 `trapframe`，让后续的 `sret` 能够从用户程序入口、使用用户栈返回到用户态执行。
- **关键实现要点**（对应 `kern/process/proc.c` 中 `load_icode` 的第 (6) 步）：
  - 先保存原 trapframe 中的 `sstatus`：`uintptr_t sstatus = tf->status;`，以便保留除特权级相关位以外的控制位（如某些保留位）。
  - 对整个 `trapframe` 清零：`memset(tf, 0, sizeof(struct trapframe));`，确保寄存器初始状态可预期。
  - **设置用户栈指针**：`tf->gpr.sp = USTACKTOP;`，令用户态第一条指令看到的 `sp` 正好指向用户栈顶。
  - **设置用户入口 PC**：`tf->epc = elf->e_entry;`，将 `ELF` 头中的入口地址写入，将来 `sret` 会跳转到该入口处执行用户代码。
  - **配置 `sstatus` 寄存器**：
    - 以保存下来的 `sstatus` 为基础：`tf->status = sstatus;`
    - 清除 `SSTATUS_SPP`，表示“从 S 态 trap 回来时的前一特权级为 U 态”，这样 `sret` 会真正切到用户态；
    - 清除 `SSTATUS_SIE`，关闭当前 S 模式下中断；
    - 置位 `SSTATUS_SPIE`，使得从 `sret` 返回到 U 态后，U 态中断使能位会被自动打开。
- **效果**：此时 `current->tf` 中已经保存了用户程序执行起点所需的 PC、SP 和特权级信息，调度到该进程并执行 `forkret/forkrets` + `sret` 后，就会以用户态从应用入口开始运行。

### 2\. 从 RUNNING 态到执行应用第一条指令的全过程

- **（1）调度器选择进程进入 RUNNING**
  - 某个内核线程（如 `init_main`）调用 `kernel_thread(user_main, ...)` 创建 `user_main`，后者再通过 `KERNEL_EXECVE` 触发 `SYS_exec`，进入 `do_execve`/`load_icode` 完成用户地址空间与 trapframe 设置。
  - 当该进程的 `state` 被置为 `PROC_RUNNABLE` 后，调度器 `schedule` 在需要切换时挑选它作为下一个运行的进程，并调用 `proc_run(proc)`。
- **（2）`proc_run` 做上下文和页表切换**
  - 在 `proc_run` 中，内核先关中断保存现场，然后：
    - 保存当前进程指针为 `prev = current`，并更新 `current = proc`；
    - 根据 `current->mm` 选择合适的页表根，调用 `lsatp(current->pgdir)` 切换到该用户进程的页表；
    - 调用 `switch_to(&prev->context, &current->context)`，在汇编中保存/恢复 `ra/sp/s0-s11` 等寄存器。
  - 由于在创建进程时 `copy_thread` 把 `current->context.ra` 设置为 `forkret`，因此 `switch_to` 返回时会跳转到内核中的 `forkret` 函数。
- **（3）从 `forkret` 到 `sret`**
  - `forkret` 的实现是调用 `forkrets(current->tf)`，这是一段汇编，用于：
    - 将 `current->tf` 中保存的通用寄存器与控制寄存器内容恢复到硬件寄存器，包括 `sepc`、`sstatus` 等；
    - 最后执行 `sret` 指令。
  - 由于在 `load_icode` 中已经将 `tf->epc` 设为 `elf->e_entry`，`tf->gpr.sp` 设为 `USTACKTOP`，`tf->status` 的 `SPP/SPIE` 等位也配置完毕，因此：
    - `sret` 会从 S 态切换到 U 态；
    - 将 `sepc` 作为新的 PC 跳转目标（即应用程序的入口地址）；
    - 将 `sp` 设为用户栈顶。
- **（4）真正执行用户程序第一条指令**
  - 当 `sret` 执行完毕，CPU 已经处于用户态，PC 指向 `elf->e_entry`，栈指针指向 `USTACKTOP`，此时流水线开始取指、译码并执行用户程序的第一条指令，用户态进程正式开始运行。

## 练习 2: 父进程复制自己的内存空间给子进程（需要编码）

### 1\. 设计与实现 `copy_range`

- **函数位置**：`kern/mm/pmm.c` 中 `int copy_range(pde_t *to, pde_t *from, uintptr_t start, uintptr_t end, bool share)`。
- **基本思路**：在 `[start, end)` 用户虚拟区间内，以页为单位遍历父进程页表，对每个存在有效映射的页：
  1. 在子进程页表中为同一虚拟地址分配相应的页表结构；
  2. 分配一块新的物理页；
  3. 将父进程页面内容整页拷贝到新物理页；
  4. 用相同的权限把新物理页映射到子进程地址空间，从而实现“内容相同但物理页独立”的地址空间复制。
- **具体实现步骤**：
  - 对于每个页对齐的 `start`：
    - 调用 `get_pte(from, start, 0)` 取得父进程对应的 PTE，如果上层页目录不存在，则将 `start` 跳过到下一个 `PTSIZE` 边界；
    - 若父进程 PTE 有效（`*ptep & PTE_V`），则调用 `get_pte(to, start, 1)` 为子进程在同一虚拟地址保证存在 PTE（必要时分配新的页表页）；
    - 取出权限位：`uint32_t perm = (*ptep & PTE_USER);`，保证子进程的访问权限与父进程一致；
    - 通过 `pte2page(*ptep)` 得到父进程的物理页 `page`，再用 `alloc_page()` 为子进程分配新物理页 `npage`；
    - 使用 `page2kva(page)` / `page2kva(npage)` 获得内核虚拟地址，`memcpy(dst_kvaddr, src_kvaddr, PGSIZE)` 完整复制一页内容；
    - 最后调用 `page_insert(to, npage, start, perm)` 建立子进程虚拟地址到新物理页的映射，并维护引用计数与 TLB 一致性。
- **正确性分析**：
  - 父子进程拥有各自独立的物理页，因此后续任一方对自己的用户空间写入不会影响另一方；
  - 页表结构通过 `get_pte(..., create=1)` 自动按需分配，能正确处理跨多个页目录 / 页表的地址区间；
  - 权限位直接来自父进程 PTE，保证了用户态可见的访问权限（读/写/执行）不被破坏。

### 2\. 如何设计实现 Copy-on-Write（COW）机制

#### (1) 基本思路与数据结构

- **核心思想**：在 `fork` 时尽量共享父进程的物理页，只在发生写访问时再为写入方拷贝出私有副本，从而减少内存占用和拷贝开销。
- **需要的扩展**：
  - 在 PTE 中预留一位作为软件标记（例如使用 RISC-V 的 `PTE_RSW` 比特）定义为 `PTE_COW`，表示该页处于 COW 共享状态；
  - 扩展物理页结构 `struct Page` 的引用计数（已有 `page_ref`），用于判断某物理页是否仍被多个进程共享；
  - 在异常处理路径（例如 `trap.c` 的 store/page-fault 分支）中增加对 COW 写异常的专门处理逻辑。

#### (2) 在 `fork`/`copy_range` 阶段的处理

- 将当前“简单拷贝”的 `copy_range` 改造成支持 COW 的版本，大致流程：
  - 遍历父进程地址空间时，对每一个**可写用户页**：
    - 不再分配新物理页并拷贝内容，而是让子进程的 PTE 直接指向同一物理页；
    - 清除父子双方 PTE 的写位 `PTE_W`，只保留读权限，并在二者 PTE 中置位 `PTE_COW`；
    - 对应物理页的 `page_ref` 会因为多次映射而增加，记录共享者数量。
  - 对于只读代码段、只读数据页，可以继续保持只读共享（甚至不必打 COW 标记），这样既节省内存也减少后续缺页处理。

#### (3) 写访问时的页故障处理

- 当某个进程对 COW 页执行写操作时，由于 PTE 已去掉写权限，硬件会触发写相关的页异常：
  - 在 Trap 入口保存上下文后，`trap_dispatch` 根据异常原因判断是“对只读页的写访问”；
  - 通过 `get_pte(pgdir, la, 0)` 查到对应 PTE，发现：
    - `PTE_W == 0`，但 `PTE_COW == 1`（软件标记），则识别为 COW 写异常；
  - COW 处理步骤：
    1. 取得当前共享物理页 `page = pte2page(*ptep)`；
    2. 若 `page_ref(page) > 1`（确实被多个进程共享）：
       - 分配新物理页 `npage = alloc_page()`；
       - 使用 `memcpy(page2kva(npage), page2kva(page), PGSIZE)` 拷贝整页内容；
       - 调用 `page_insert(pgdir, npage, la, 新权限)`，其中“新权限”重新开启写位 `PTE_W`，并清除 `PTE_COW`；
       - 对旧物理页执行 `page_ref_dec`，如引用计数降为 1，可解除 COW 状态（清除剩余映射中的 `PTE_COW` 或在后续懒处理）。
    3. 若 `page_ref(page) == 1`，说明实际上已经没有其他共享者，可以直接在当前 PTE 上恢复写权限（置位 `PTE_W` 并清除 `PTE_COW`），避免额外拷贝。
  - 最后返回 Trap 处理流程，重新执行造成异常的指令，此时该进程已经拥有一个可写的私有页。

#### (4) 其他配套修改

- **进程退出与回收**：`exit_mmap`/`page_remove_pte` 仍通过页引用计数和 `free_page` 回收物理页，COW 仅改变共享策略，不改变最终回收路径。
- **权限与安全性**：在任何时候，COW 页在硬件层面都是只读的，只有在内核完成“拷贝+重新插入”或“解除 COW 恢复写权限”之后，才会重新开放写权限，避免用户态越权修改共享页。

---

## 练习 3: 阅读分析源代码，理解进程执行 fork/exec/wait/exit 的实现

### 1\. fork/exec/wait/exit 的执行流程分析

在 uCore 中，进程控制主要涉及到 `do_fork`, `do_execve`, `do_wait`, `do_exit` 这四个核心函数。它们的执行流程涉及用户态与内核态的切换。

#### (1) fork 创建进程

  * **执行流程：**
    1.  程序在用户态调用 `fork()` 系统调用。
    2.  通过 `ecall` 指令触发 Trap，进入内核态，最终调用 `do_fork` 函数。
    3.  `do_fork` 分配一个新的 `proc_struct` PCB。
    4.  调用 `copy_mm` 复制父进程的内存空间。
    5.  调用 `copy_thread` 复制父进程的 Trapframe 和上下文。关键在于将子进程 Trapframe 中的返回值寄存器 `a0` 设置为 0，而父进程的返回值为子进程 PID。
    6.  将子进程状态设置为 `PROC_RUNNABLE` 并加入就绪队列。
    7.  内核态返回，父进程和子进程分别从 `fork()` 调用处继续执，但在用户态获得的返回值不同。

#### (2) exec 加载新程序

  * **执行流程：**
    1.  用户态调用 `exec()`。
    2.  进入内核态，调用 `do_execve`。
    3.  检查内存空间，如果当前进程拥有内存空间`mm`，则清空并释放，准备加载新程序。
    4.  调用 `load_icode` 加载 ELF 格式的二进制程序。这包括建立新的内存映射、分配栈空间、处理 BSS 段等。
    5.  修改当前进程 Trapframe 中的 `epc` 程序计数器为 ELF 文件的入口地址，重置 `sp` 栈指针为新的用户栈顶。
    6.  `do_execve` 返回，系统执行 `sret` 从内核态返回用户态。此时 CPU 跳转到新程序的入口地址执行，旧程序的上下文完全被替换。

#### (3) wait 等待子进程

  * **执行流程：**
    1.  用户态调用 `wait()`。
    2.  进入内核态，调用 `do_wait`。
    3.  父进程遍历自己的子进程列表。
    4.  如果发现有子进程处于 `PROC_ZOMBIE` 僵尸状态，则回收该子进程的剩余资源，如内核栈、PCB，并获取其退出码，返回用户态。
    5.  如果子进程都在运行，父进程将自己状态设为 `PROC_SLEEPING` 并调用 `schedule`主动放弃 CPU，调用 `schedule`），等待被唤醒。
    6.  当子进程 `exit` 退出时`exit`，会唤醒父进程。

#### (4) exit 进程退出

  * **执行流程：**
    1.  用户态调用 `exit()` 或程序结束。
    2.  进入内核态，调用 `do_exit`。
    3.  释放进程的大部分资源，虚拟内存空间 `mm`，但保留 PCB 和内核栈以便父进程查询。
    4.  将状态设置为 `PROC_ZOMBIE`。
    5.  如果该进程有子进程，将子进程挂载到 `init` 进程 PID 1下，由 `init` 负责回收。
    6.  唤醒父进程。
    7.  调用 `schedule` 调度其他进程执行。
  * **哪些在用户态，哪些在内核态？**

      * **用户态：** 发起系统调用的初始动作，设置参数、执行 `ecall`，以及系统调用返回后的后续逻辑。
      * **内核态：** 资源的分配与回收，如内存、PCB、上下文切换、ELF 解析与加载、进程状态的变更、调度决策。

  * **内核态与用户态程序如何交错执行？**

      * 通过系统调用、中断和异常进行切换。用户程序运行 -\> 触发 Trap (ecall) -\> 硬件保存状态 -\> 内核处理 -\> 内核恢复状态 (sret) -\> 用户程序继续运行。

  * **内核态执行结果如何返回给用户程序？**

      * 通过修改Trapframe中断帧中的寄存器。
      * 返回值通常保存在 `a0` 寄存器中。内核在处理完系统调用后，将结果写入当前进程 Trapframe 的 `a0` 处。当执行 `sret` 返回用户态时，硬件会将 Trapframe 中的值恢复到 CPU 寄存器，用户程序便能读取到返回值。

### 2\. 用户态进程的执行状态生命周期图

```text
       (alloc_proc)          (scheduler)
[UNINIT] --------> [RUNNABLE] <--------> [RUNNING]
                      ^    |                 |
                      |    |                 | (do_exit)
            (wakeup)  |    | (do_wait)       |
                      |    v                 v
                   [SLEEPING]            [ZOMBIE]
                                             |
                                             | (parent waits)
                                             v
                                          [DEAD]
```


## 扩展练习 Challenge2 

**问题：说明该用户程序是何时被预先加载到内存中的？与我们常用操作系统的加载有何区别，原因是什么？**

### 1\. 用户程序被加载到内存的时机

用户程序是随内核镜像Kernel Image一起被加载到内存中的。

  * **具体机制：** 实验构建系统（Makefile）会将编译好的用户程序二进制代码链接到内核的可执行文件中（通常通过链接脚本或宏定义 `macros.S` 中的 `.incbin` 等指令）。
  * **物理位置：** 当 Bootloader 将 uCore 内核加载到物理内存时，这些用户程序的二进制数据就已经作为内核数据的一部分存在于物理内存中了。
  * **执行时：** 当 `do_execve` 调用 `load_icode` 时，它并不是从磁盘读取文件，而是直接从内存中的某个特定位置（指向该用户程序的指针）拷贝内容建立新的内存映射。

### 2\. 与常用操作系统的区别

| 特性 | uCore | Linux/Windows |
| :--- | :--- | :--- |
| **存储位置** | 编译进内核镜像，常驻物理内存。 | 存储在磁盘的文件系统中。 |
| **加载方式** | 一次性全部存在。`exec` 时从内核数据区映射。 | 按需加载 。`exec` 仅读取头部，执行时通过缺页异常动态从磁盘加载页面。 |


### 3\. 造成这种区别的原因
一方面是为了避免引入复杂的文件系统代码和磁盘 I/O 操作，将用户程序直接嵌入内存是最简单的实现方式，另一方面硬件设施也有限。
