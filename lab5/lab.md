# Lab 5 实验报告

## 练习 1: 加载应用程序并执行（需要编码）

### 1\. 设计与实现 `load_icode` 第 6 步 trapframe 初始化

- **整体思路**：在前面几步完成用户地址空间建立，即为各个 `ELF` 段建立 `vma`、分配物理页并拷贝代码/数据、建立 BSS、创建用户栈以及切换到新的用户页表之后，通过设置当前进程 `proc_struct` 中的 `trapframe`，让后续的 `sret` 能够从用户程序入口、使用用户栈返回到用户态执行。
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
  - 页表结构通过 `get_pte` 自动按需分配，能正确处理跨多个页目录 / 页表的地址区间；
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

## Lab5 Challenge1：Copy-on-Write（COW）机制设计与实现

### 1. 目标与背景

本扩展练习要求在 uCore（RISC-V）中实现 **Copy-on-Write（COW）fork**：

- fork 时不再复制父进程全部用户页，而是让父子进程**共享物理页**；
- 共享期间将对应虚拟页映射设置为**只读**；
- 当任一进程尝试写该页时，硬件触发 **store page fault**，内核在缺页异常处理中完成**按需拷贝**，使写入进程获得私有页。

这样可以显著降低 fork 的内存拷贝开销，并保持父子隔离语义：一个进程对内存的修改对另一个进程不可见。


### 2. 关键数据结构与位语义

#### 2.1 页表项软件位：`PTE_COW`

实现中使用 `lab5/kern/mm/mmu.h` 中 `PTE_SOFT (0x300)` 的一个 bit 作为 **COW 标记**：

- `PTE_COW (0x100)`：表示该页为 **COW 共享页**。

核心约定：

- 若页表项带 `PTE_COW`，则该页必须**不可写（清 `PTE_W`）**；
- 对该页写入会触发 store page fault，进入 COW 处理流程；
- 完成 COW 后会清除 `PTE_COW`，并恢复 `PTE_W`（变为私有可写页）。

#### 2.2 物理页引用计数：`struct Page::ref`

物理页引用计数用于判断是否需要拷贝：

- `ref > 1`：仍被多个地址空间映射，写入方需要 **分配新页并 memcpy**；
- `ref == 1`：仅当前地址空间持有该物理页，写入方无需拷贝，可直接 **清 COW 并恢复可写**（快路径）。

引用计数由 `page_insert/page_remove_pte` 维护。

#### 2.3 并发与锁：`mm->mm_lock`

页故障处理和页表更新需要串行化，避免同一进程/同一地址空间内并发修改页表导致不一致：

- `do_pgfault` 在修改页表前会 `lock_mm(mm)`。



### 3. fork 时的 COW 共享策略

COW 的关键在 fork 阶段：不拷贝物理页，只"改权限 + 打标记"。

实现位置：

- `lab5/kern/mm/vmm.c: dup_mmap()`：将 `share` 置为 1，使 `copy_range(..., share=1)` 走 COW。
- `lab5/kern/mm/pmm.c: copy_range()`：新增 share 分支。

#### 3.1 COW 规则

对每个有效 PTE：

- 若原 PTE 含 `PTE_W`，可写用户页：
  - 父 PTE：清 `PTE_W`，置 `PTE_COW`，只读+COW
  - 子 PTE：映射到同一物理页，清 `PTE_W`，置 `PTE_COW`
- 若原 PTE 不可写，例如代码段只读：
  - 父/子均共享只读映射，不置 `PTE_COW`

#### 3.2 TLB 一致性

父进程页表的权限被降级后，必须失效对应 TLB：

- 正常实现：调用 `tlb_invalidate(from, la)`
- 否则可能出现"页表已只读，但 TLB 仍认为可写"的不一致。



### 4. page fault 路径与 COW 写时拷贝

实现位置：

- `lab5/kern/trap/trap.c`：在 `CAUSE_{FETCH,LOAD,STORE}_PAGE_FAULT` 中调用 `do_pgfault()`。
- `lab5/kern/mm/vmm.c`：实现 `do_pgfault()`。

#### 4.1 处理流程概览

1. 根据 `addr (stval)` 找到对应 `vma`，校验地址合法性；
2. 若是写入且 `PTE_COW`：进入 COW 分支；
3. COW 分支根据 `refcount` 决定：
   - `ref>1`：分配新页、拷贝内容、用可写私有页替换映射
   - `ref==1`：直接恢复可写并清除 `PTE_COW`
4. 非 COW 的一般缺页：为该虚拟页分配物理页并建立映射，增强健壮性。


### 5. COW 状态机


#### 5.1 状态说明

| 状态 | 含义 | PTE 特征 |
|------|------|----------|
| **Unmapped** | 该虚拟页未建立映射 | PTE 无效 |
| **PrivateWritable** | 私有可写页，正常执行无异常 | `PTE_W` 置位，无 `PTE_COW` |
| **SharedReadOnly** | 本来就只读的共享页（代码段等） | 无 `PTE_W`，无 `PTE_COW` |
| **CowSharedReadOnly** | fork 后由可写页降级而来 | 无 `PTE_W`，有 `PTE_COW` |

#### 5.2 状态迁移说明

| 迁移 | 触发条件 | 操作 |
|------|----------|------|
| `forkDowngradeToRO+setCOW` | fork 阶段对可写页 | 父子均：清 `PTE_W`，置 `PTE_COW`，`ref++` |
| `writeFault(ref==1,clearCOW+setW)` | 写 COW 页，仅自己持有 | 清 `PTE_COW`，恢复 `PTE_W`（无需拷贝） |
| `writeFault(ref>1,allocCopy+remapW)` | 写 COW 页，共享仍存在 | 分配新页，memcpy，重映射为可写，`ref--` |
| `unmapOrExit` | 进程退出或解除映射 | `ref--`，若 `ref==0` 则释放物理页 |


### 6. Dirty COW 风格漏洞模拟与修复

> 参考资料：https://dirtycow.ninja/ 及 https://github.com/dirtycow/dirtycow.github.io/wiki/VulnerabilityDetails

#### 6.1 真实 Dirty COW 漏洞原理（CVE-2016-5195）

Dirty COW（CVE-2016-5195）是 2016 年在 Linux 内核中发现的一个严重权限提升漏洞，该漏洞自 2007 年（内核 2.6.22）起就已存在，直到 2016 年 10 月才被修复。
漏洞本质是竞态条件（Race Condition）漏洞的核心是 Linux 内核内存子系统中处理**私有只读内存映射的 COW 机制**时存在的竞态条件。

**正常 COW 流程**：

1. 进程 mmap 一个只读文件到私有内存区域
2. 尝试写入时触发 page fault
3. 内核进行 COW：分配新页、拷贝内容、建立可写映射
4. 写入操作在**私有副本**上完成，原文件不受影响

**漏洞利用的竞态**：攻击者利用两个并发线程：

- **线程 A**：通过 `/proc/self/mem` 或 `ptrace(PTRACE_POKEDATA)` 写入只读映射
- **线程 B**：循环调用 `madvise(MADV_DONTNEED)` 丢弃页面

**竞态窗口时序**：

```
线程A: get_user_pages() -> faultin_page() -> handle_mm_fault()
                                            |
                              COW 完成，准备写入私有副本
                                            |
                              [竞态窗口] 此时页面标记为"已完成COW"
                                            |
线程B: madvise(MADV_DONTNEED) -> 丢弃刚分配的私有页
                                            |
线程A: 继续写入 -> 但私有页已被丢弃！
                                            |
                              内核重新获取页面，但由于 FOLL_WRITE 标志
                              已被错误地清除，获取到的是原始只读页！
                                            |
                              写入操作"写穿"到原始只读文件！
```

##### 6.1.2 漏洞危害

- **权限提升**：普通用户可修改 `/etc/passwd`、`/bin/su` 等只读系统文件
- **绕过 DAC**：完全绕过 Unix 的自主访问控制（Discretionary Access Control）
- **隐蔽性强**：不留日志痕迹，难以检测
- **影响范围广**：几乎所有 2007-2016 年的 Linux 发行版都受影响

##### 6.1.3 Linux 官方修复方案

Linux 内核引入 `FOLL_COW` 标志位，结合 PTE 的 dirty 位来验证 COW 是否真正完成：

```c
// 修复前：仅依赖 FOLL_WRITE 标志，可被竞态清除
// 修复后：引入 FOLL_COW，并检查 pte_dirty()
if ((flags & FOLL_COW) && pte_dirty(pte)) {
    // COW 确实完成，可以安全写入私有副本
}
```

#### 6.2 本实验中的等价漏洞构造

由于真实 Dirty COW 依赖 Linux 特有的 `/proc/self/mem`、`madvise` 等机制，难以在 uCore 中完全复现。因此本实验采用**等效模拟**方式，在**后果层面**重现"写穿共享页"的效果。

##### 6.2.1 模拟策略

提供编译期开关 `-DCOW_DIRTY_VULN`，故意引入以下缺陷：

| 正常实现 | 漏洞模拟（`-DCOW_DIRTY_VULN`） |
|---------|-------------------------------|
| fork 时父进程页表降权（清 `PTE_W`，置 `PTE_COW`） | **跳过**父进程页表降权 |
| 降权后执行 `tlb_invalidate()` 刷新 TLB | **跳过** TLB 刷新 |
| 父进程写入触发 page fault -> COW 拷贝 | 父进程通过陈旧 TLB 项**直接写穿共享页** |

##### 6.2.2 真实漏洞 vs 模拟漏洞对比

| 维度 | 真实 Dirty COW | 本实验模拟 |
|------|---------------|-----------|
| 触发方式 | 多线程竞态 + `madvise` | 编译期开关跳过关键步骤 |
| 攻击复杂度 | 需精确控制时序窗口 | 确定性触发 |
| 漏洞根因 | `FOLL_WRITE` 标志处理错误 | TLB 与页表不一致 |
| **后果** | **写穿只读共享页** | **写穿只读共享页** |
| 危害等级 | 可修改任意只读文件 | 子进程可见父进程修改 |

两者在**后果层面等价**：都绕过了 COW 机制应有的隔离保护，导致对共享页的非授权写入。

##### 6.2.3 代码实现

漏洞模拟的关键代码位于 `lab5/kern/mm/pmm.c: copy_range()`：

```c
#ifndef COW_DIRTY_VULN
    // 正常实现：父进程页表降权 + TLB 刷新
    *ptep = (*ptep & ~PTE_W) | PTE_COW;
    tlb_invalidate(from, start);
#else
    // 漏洞模拟：故意跳过降权和 TLB 刷新
    cprintf("[COW_VULN] SKIP parent downgrade/tlb_inv at 0x%lx\n", start);
#endif
```

演示用例：`lab5/user/cowdirty.c`

#### 6.3 修复方案与为何有效

正常实现（未定义 `COW_DIRTY_VULN`）下：

- fork 阶段对父页表降权后立即执行 `tlb_invalidate(from, la)`（底层为 `sfence.vma la`）。

这保证：

1. **页表权限正确**：父进程 PTE 变为只读 + COW
2. **TLB 一致性**：`sfence.vma` 强制刷新 TLB 缓存
3. **写入必触发异常**：任何后续写入都必须重新查页表，发现只读后触发 store page fault
4. **COW 正确执行**：`do_pgfault` 进行按需拷贝，父子进程获得独立副本

#### 6.4 教训与启示

1. **TLB 一致性是关键**：页表权限变更后**必须**失效 TLB，否则 CPU 可能使用陈旧的翻译
2. **竞态条件难以发现**：真实 Dirty COW 潜伏 9 年才被发现，说明并发 bug 的隐蔽性
3. **防御深度**：即使有 COW 机制，也需要配合正确的 TLB 管理、锁保护等多层防御


### 7. 测试用例说明

#### 7.1 功能正确性测试：`cowtest.c`

位置：`lab5/user/cowtest.c`

测试覆盖：
- fork 后父子进程共享只读 COW 页
- 父/子任一方写入触发 COW 拷贝
- 写入后父子隔离（修改互不可见）
- `ref==1` 快路径（直接恢复可写，无需拷贝）

预期输出：`cowtest pass.`

运行方式：
```bash
cd lab5
bash tools/test_cow.sh  # COW 功能测试脚本
```

#### 7.2 漏洞演示测试：`cowdirty.c`

位置：`lab5/user/cowdirty.c`

测试目的：
- 在 fork 前"预热"可写页，使其翻译缓存进 TLB
- fork 后父进程立即写入该页
- 正常实现：应触发 COW，子进程不可见
- 漏洞演示：父进程写穿共享页，子进程可见

预期输出：
- 正常构建：`dirtycow not vulnerable.`
- 漏洞演示构建（`-DCOW_DIRTY_VULN`）：`dirtycow vulnerable (demo).`

运行方式：
```bash
cd lab5
bash tools/test_cow_vuln.sh  # 漏洞演示脚本，自动编译并运行
```


### 8. 演示与验证步骤

#### 8.1 验证 COW 功能正确性

```bash
cd lab5
bash tools/test_cow.sh
```

脚本会自动清理、编译（带 `-DENABLE_COW`）并运行 `cowtest`。

成功时输出：
```
======================================================================
COW 功能测试通过！

验证内容：
  • fork 后父子共享物理页（只读+COW 标记）
  • 子进程写入触发 COW 拷贝
  • 父子修改互不可见（隔离验证）
```

#### 8.2 演示 Dirty COW 风格漏洞

```bash
cd lab5
bash tools/test_cow_vuln.sh
```

脚本会：
1. 清理旧构建
2. 用 `-DENABLE_COW -DCOW_DIRTY_VULN` 宏编译内核
3. 运行 `cowdirty` 测试
4. 检查输出是否为 `dirtycow vulnerable (demo).`

成功时输出：
```
======================================================================
 Dirty COW 漏洞演示成功！

漏洞原理（CVE-2016-5195 风格）：
  1. fork 时父进程页表本应降权为只读，但 TLB 未刷新
  2. 父进程使用陈旧的 TLB 条目，仍有可写权限
  3. 父进程写入直接穿透到共享物理页
  4. 子进程看到了父进程的修改 → 隔离被破坏

修复方案：
  • fork 后必须对父进程执行 TLB 刷新（sfence.vma）
  • 确保页表权限变更立即生效
```


### 9. 调试过程记录

#### 9.1 初始问题诊断

在实现过程中遇到的主要问题：

**问题1**：`cowtest` 子进程 assert 失败

- 现象：`user panic at user/cowtest.c:48: assertion failed: g_value == 0x22222222`
- 原因：子进程第二次 yield 后读取 `g_value`，期望仍为 `0x22222222`，但实际不是
- 诊断：添加日志发现父进程写入后触发了 COW，但子进程的映射可能未正确更新
- 修复：在 `proc_run` 中添加 `flush_tlb()`，确保切换进程时刷新 TLB

**问题2**：漏洞演示构建中宏未生效

- 现象：即使定义 `-DCOW_DIRTY_VULN`，仍输出 `dirtycow not vulnerable.`
- 原因：`grade.sh` 传递 `DEFS+=` 参数时，引号处理与 Makefile 嵌套调用冲突
- 诊断：通过添加条件编译日志（`cprintf("[COW_VULN]..."` vs `"[COW_NORMAL]..."`）确认宏未定义
- 修复：创建独立的 `build-cowdirty` Makefile 目标和 `test_cow_vuln.sh` 脚本

**问题3**：漏洞演示测试偶发失败

- 现象：运行 `bash tools/test_cow_vuln.sh` 偶尔输出 `Dirty COW 漏洞演示失败`
- 原因：存在旧的编译缓存（`.o` 文件），`make clean` 未完全清理，导致新的 `-DCOW_DIRTY_VULN` 宏未生效
- 修复：确保脚本中的 `make clean` 正确执行，或手动执行 `make clean` 后重试
- 验证：重新运行脚本，应看到 `[COW_VULN] SKIP parent downgrade/tlb_inv at ...` 的日志输出

### 9.2 关键调试技巧

1. **条件编译日志**：在 `#ifdef/#else` 分支中添加不同的 cprintf 输出，快速确认宏定义状态
2. **refcount 追踪**：在 COW fork 和 page fault 路径打印 `page_ref(page)`，验证共享/拷贝逻辑
3. **PTE 标志检查**：打印 PTE 值，确认 `PTE_W/PTE_COW` 位的设置与清除
4. **进程切换追踪**：在 `proc_run` 中打印切换信息，验证 TLB 刷新时机

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

## lab2 额外任务
QEMU 地址翻译流程与关键路径分析通过“双重 GDB 调试”，我深入 QEMU 源码层`qemu-4.1.1`，追踪了 ucore 在模拟器中的访存行为。
### 调试过程

#### 1. 终端 T1
**命令**：`make debug`
* **角色**：**被调试对象 (QEMU 进程)**
* **工作内容**：
* 启动 `qemu-system-riscv64` 模拟器进程。
* 它模拟了一台 RISC-V 计算机。
* 在实验开始时，它处于“冻结”状态，等待来自 T3 的 GDB 连接指令；在实验过程中，它负责实际执行 ucore 的机器码，并运行 C 语言编写的模拟逻辑。

#### 2. 终端 T2 
**命令**：`sudo /home/bbchan/anaconda3/bin/gdb` -> `attach <PID>`
* **角色**：**调试 QEMU 的 GDB**
* **工作内容**：
* **挂载进程**：使用 Linux 的 `ptrace` 机制侵入正在运行的 QEMU 进程。
* **设置陷阱**：在 QEMU 的源码中设置断点，拦截模拟硬件的关键行为。
* **观察硬件**：在 ucore 运行过程中，单步调试 QEMU 的 C 代码，观察虚拟硬件是如何一步步解析虚拟地址、查找 TLB 和遍历页表的。

#### 3. 终端 T3
**命令**：`make gdb`
* **角色**：**调试 ucore 的 GDB**
* **工作内容**：
* **控制执行**：通过 TCP 端口连接到 QEMU 的 GDB Stub。
* **驱动系统**：发送 `continue` 指令，QEMU开始执行 ucore 的代码。
* **常规调试**：这是平时做实验用的窗口，用于查看 ucore 的变量、堆栈和寄存器状态。但在本次实验中，它主要作为“触发器”，通过让 OS 运行来触发 T2 中的硬件断点。


### 1.1 关键调用路径当 ucore 执行一条访存指令时，QEMU 的处理流程如下：

1. **TLB Lookup (Fast Path)**: QEMU 首先查询软件 TLB。如果命中，直接返回物理地址。
2. **TLB Miss**: 如果未命中，触发 Slow Path。
3. **TLB Fill**: 调用 `riscv_cpu_tlb_fill` ，位于 `cpu_helper.c`。
4. **Hardware Walk**: 调用 `get_physical_address`。这是模拟硬件 MMU 行为的核心函数。

### 1.2 关键分支演示在调试 `get_physical_address` 时，我观察到了两种地址翻译模式，对应了 ucore 启动的两个阶段：

* **阶段一：直接映射 (Bare Mode)**
* **场景**：ucore 刚启动，PC 位于 `0x80200000`。
* **分支逻辑**：代码读取 `satp` 寄存器，判断 Mode 为 0。
* **代码行为**：直接跳过了查表循环，执行 `*physical = addr;`。
* **原理**：此时 OS 尚未开启分页，虚拟地址等同于物理地址。


* **阶段二：SV39 分页翻译 (Paging Mode)**
* **场景**：ucore 初始化完毕，PC 跳转至高地址 `0xffffffff...`。
* **分支逻辑**：代码检测到 `satp` 的 MODE 字段为 SV39，进入 `VM_1_10_SV39` 分支。
* **代码行为**：执行一个 `for` 循环，模拟多级页表查找。


### 2. 单步调试页表翻译 (Hardware Page Table Walk)在捕获到分页模式的访存后，我对 `get_physical_address` 中的核心循环进行了单步调试。以下是代码与原理的对应分析：

#### 2.1 关键操作流程解释调试中观察到的核心代码片段如下：

```
If (masked_msbs != 0 && masked_msbs != mask) {
(gdb) n
231         int ptshift = (levels - 1) * ptidxbits;
(gdb) n
237         for (i = 0; i < levels; i++, ptshift -= ptidxbits) {
(gdb) n
238             target_ulong idx = (addr >> (PGSHIFT + ptshift)) &
(gdb) n
239                                ((1 << ptidxbits) - 1);
(gdb) n
238             target_ulong idx = (addr >> (PGSHIFT + ptshift)) &
(gdb) n
242             target_ulong pte_addr = base + idx * ptesize;
(gdb) n
244             if (riscv_feature(env, RISCV_FEATURE_PMP) &&
(gdb) n
245                 !pmp_hart_has_privs(env, pte_addr, sizeof(target_ulong),
(gdb) n
244             if (riscv_feature(env, RISCV_FEATURE_PMP) &&
(gdb) n
252             target_ulong pte = ldq_phys(cs->as, pte_addr);
(gdb) n
254             target_ulong ppn = pte >> PTE_PPN_SHIFT;
```

* SV39 使用三级页表，所以 `levels` 为 3。
* 循环体每执行一次，代表硬件查询了一级页表。`i=0` 查 L2 页表，`i=1` 查 L1 页表，`i=2` 查 L0 页表。

* `idx = (addr >> ...) & ...`：这是在对 64 位的虚拟地址进行位切片，提取出当前级别的虚拟页号作为索引。
* `ldq_phys(cs->as, pte_addr)`：`ldq` 意为 "Load Quad-word"。这行代码模拟了 CPU 的 MMU 向物理内存总线发起读取请求，根据计算出的物理地址 `pte_addr` 获取页表项 (PTE) 的内容。



### 3. TLB 查找机制与细节
#### 3.1 查找 TLB 的 C 代码在 QEMU 源码中，模拟 CPU 查找 TLB 的“动作”主要体现在 **TLB Miss 之后的填充过程**。

* **代码位置**：`target/riscv/cpu_helper.c` 中的 `riscv_cpu_tlb_fill` 函数。
* **调试细节**：
按照 RISC-V 流程，确实是“先查 TLB，Miss 后再查页表”。
在调试中，我们之所以能断点停在 `get_physical_address`，正是因为TLB Miss 发生了。如果 TLB Hit，QEMU 会直接使用缓存的地址，不会执行这个 C 函数。
因此，调试到了这个函数，本身就证明了查找 TLB 失败 -> 触发 Refill 逻辑这一过程。

#### 3.2 软件 TLB vs. 硬件 TLB 的逻辑区别* 
真实 CPU 使用 CAM 电路进行并行查找，极其快速；QEMU 使用虚拟地址高位作为索引进行哈希数组查找。
Miss 处理是真实 CPU 由硬件状态机自动完成漫游，不暂停指令流；QEMU 则通过函数调用暂停当前指令块的执行，调用 C 函数去查表。
Bare Mode 行为调试发现，即使在关闭分页的 Bare Mode 下，QEMU 依然会调用 `tlb_fill`。这说明 QEMU 的逻辑是通用的：它缓存的是“翻译结果”，哪怕这个结果是 `VA=PA`。

### 4. 调试过程中的困难####
**GDB 的权限地狱**：
在尝试 `attach` 到 QEMU 进程时，GDB 报错 `ptrace: Operation not permitted`。查阅资料后发现这是 Ubuntu 的安全机制。不得不使用 `sudo gdb`。
但抓马的是，用了 `sudo` 后，因为环境变量重置，系统找不到我 Conda 环境里的 `riscv64-gdb` 了。最后用 `which` 命令寻找的 gdb 戏码，使用 `sudo $(which gdb)` 才成功启动。
2. **Packet Error**：
当我在 T2 暂停了 QEMU 后，T3的 GDB 突然报错 `Ignoring packet error`。以为实验环境崩了，后来发现是时序问题，加了条 remotetime unlimited 指令就好了。


### 5. 大模型辅助调试记录

**环境配置困境（sudo 找不到命令）**

* **情况**：在调试 QEMU 时，我输入 `sudo gdb` 却提示 `command not found`。但是不用 sudo 时 `gdb` 明明是可以运行的。
* **解决**：我询问大模型原因。AI 解释了 Linux 中 `sudo` 命令为了安全会重置 `$PATH` 环境变量，导致系统不去 Conda 的目录下寻找程序。AI 给出了 `sudo $(which gdb)` 这一巧妙的组合命令，直接解决了路径问题。



**现象分析**

* **情况**：第一次断点在 `get_physical_address` 时，单步调试发现代码直接从“读取 MODE”跳到了“返回物理地址”，中间核心的查表循环全被跳过了。
* **解决**：我向 AI 描述了这一现象。AI 提示我检查当前的 CPU 模式，并指出在 OS 启动初期是 **Bare Mode**，此时 QEMU 正确地执行了 `if` 判断并跳过了查表。



## lab5 额外任务系统调用与特权级切换的双重观测：基于 QEMU 源码的指令行为分析

在完成了 Lab 2 的地址翻译观测后，我再次利用“双重 GDB 调试”方案，针对系统调用进行了微观观测。本次实验重点在于追踪 RISC-V 架构下用户态与内核态切换的物理实现。

### 架构

#### 1. 终端 T1 
**命令**：`make debug`

* **状态**：QEMU 启动并暂停，等待连接。此时它准备模拟执行 ucore 的内核代码以及即将加载的用户程序 `exit.c`。

#### 2. 终端 T2
**命令**：`sudo gdb -p <PID>`

* **断点策略**：本次我并未在内存访问函数打断点，而是拦截了 QEMU 处理特权指令的 Helper Functions。
* 拦截进入内核：`break helper_raise_exception`
* 拦截返回用户：`break helper_sret`

在 ucore 触发异常或执行返回指令时，暂停 QEMU 进程，让我看到 `ecall` 和 `sret` 这两条汇编指令背后的 C 语言实现逻辑。

#### 3. 终端 T3
**命令**：`make gdb`

* **关键配置**：
* `set remotetimeout unlimited`：防止在 T2 暂停 QEMU 思考时，T3 因为超时而断开连接。
* `add-symbol-file obj/__user_exit.out`：加载用户程序的调试符号，否则 GDB 无法识别用户态的 `syscall` 函数。


* **工作内容**：控制 ucore 单步执行到 `ecall` 前夕，作为触发器激活 T2 的断点。


`ecall` 与 `sret` 的 QEMU 源码处理流程通过调试，看到通过调用 C 语言函数来修改 `CPUArchState` 结构体中的状态变量。

#### 1.1 `ecall` 的处理 (U -> S)当 ucore 执行 `ecall` 时，T2 捕获到了 `helper_raise_exception` 函数的调用。

* **源码逻辑分析** (`target/riscv/op_helper.c`)：
1. **保存原因**：代码将 `env->scause` 设置为 `RISCV_EXCP_U_ECALL` (8)，标记异常来源为用户态系统调用。
2. **保存现场**：将当前的指令地址 `env->pc` 赋值给 `env->sepc`，作为日后的返回地址。
3. **状态保存与切换**：读取 `sstatus`，将当前的特权级 (User/0) 保存到 `SPP` 位，并禁用中断。
4. **特权级提升**： 最关键的一步是直接修改结构体变量 `env->priv = PRV_S`，这就完成了物理上的特权级切换。
5. **跳转**：将 `env->pc` 重置为 `env->stvec`（内核中断入口），指向 `__alltraps`。



#### 1.2 `sret` 的处理 (S -> U)
当 ucore 完成处理执行 `sret` 时，T2 捕获到了 `helper_sret`。

* **源码逻辑分析**：
1. **读取目标特权级**：代码从 `mstatus` (或 `sstatus`) 的 `SPP` 位中读出之前保存的特权级（User/0）。
2. **恢复 PC**：将 `env->pc` 恢复为 `env->sepc`（即 `ecall` 的下一条指令）。
3. **特权级降级**：执行 `env->priv = prev_priv`，CPU 瞬间回到了用户态。




### 2. TCG 指令翻译
为什么能在 C 代码中拦截到汇编指令？我通过询问AI获得了答案，这涉及到了 QEMU 的 **TCG (Tiny Code Generator)** 机制。

* **功能理解**：
QEMU 使用动态二进制翻译 (JIT) 技术。对于简单的算术指令（如 `add`），TCG 会将其直接翻译为宿主机的汇编指令（Fast Path），速度极快且无法用 C 断点拦截。
但对于 `ecall`、`sret` 这类涉及复杂系统状态变更的指令，或者 Lab 2 中的 **TLB Miss** 场景，TCG 会生成代码调用预编译好的 **C Helper Functions**。

这与 Lab 2 的双重调试本质是一致的。双重 GDB 调试实际上就是观测 TCG 在处理“困难指令”时的 C 语言慢速路径。


### 3. 调试困难
**僵尸进程**：
调试初期频繁遇到 `Address already in use` 报错。排查发现是之前 Lab 2 调试结束后未彻底关闭 QEMU，导致后台残留了多个“僵尸”进程占用了 1234 端口。用 `killall -9 qemu-system-riscv64` 解决了问题。



### 4. 大模型辅助调试记录

**问题一：如何拦截系统调用？**

* **情景**：我知道 `ecall` 会触发异常，但不知道 QEMU 源码中对应的 C 函数名叫什么。
* **交互**：询问 AI “QEMU RISC-V source code function handling ecall”。
* **解决**：AI 准确定位到了 `target/riscv/op_helper.c` 中的 `helper_raise_exception` 函数，节省了大量的 grep 时间。

**问题二：GDB 连接频繁超时**

* **情景**：当我在 T2 暂停 QEMU 进行思考分析时，T3 的 GDB 总是报错 `Remote communication error` 并断开。
* **解决**：将报错发给 AI，AI 解释是因为 QEMU 暂停导致无法响应 T3 的握手包，并给出了 `set remotetimeout unlimited` 这一关键指令，彻底解决了连接不稳定的问题。

**问题三：找不到用户程序符号**

* **情景**：在 T3 试图 `break syscall` 时提示 `Function not defined`。
* **交互**：询问 AI “如何调试 ucore 中的用户态程序 exit.c”。
* **解决**：AI 指出 `make debug` 默认只加载内核符号，必须使用 `add-symbol-file` 手动加载用户程序的 ELF 文件。
