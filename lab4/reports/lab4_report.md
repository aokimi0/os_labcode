# <center> Lab4 内存管理 </center>

<center> 金莫迪 廖望 李星宇 </center>

## 实验目的

- 了解虚拟内存管理的基本结构，掌握虚拟内存的组织与管理方式
- 了解内核线程创建/执行的管理过程
- 了解内核线程的切换和基本调度过程

## 实验


### 练习0：填写已有实验

#### 实现内容

- **物理内存管理部分填写**  
  在 `lab4/kern/mm/default_pmm.c` 中，将 Lab2 实现的 first-fit 物理内存分配器整体迁移过来，替换 `// LAB2` 处的占位实现，核心包括：
  - 使用 `free_area_t` 维护按地址有序的空闲块链表 `free_list` 与空闲页计数 `nr_free`；
  - 在 `default_init_memmap` 中初始化每个 `Page` 的 `flags/property/ref` 字段，并将首页挂入空闲链表；
  - 在 `default_alloc_pages` 中按 first-fit 策略查找首个满足 `property >= n` 的块，必要时拆分剩余部分并更新 `nr_free`；
  - 在 `default_free_pages` 中插入并尝试向前/向后合并相邻空闲块，维护正确的 `property` 与 `nr_free`。

- **时钟中断处理部分填写**  
  在 `lab4/kern/trap/trap.c` 的 `IRQ_S_TIMER` 分支处，填入 Lab3 中实现的时钟中断逻辑，保持原有 “LAB3 EXERCISE1 YOUR CODE” 注释：
  - 调用 `clock_set_next_event()` 安排下一次时钟中断；
  - 使用全局 `ticks` 计数，每当 `ticks % 100 == 0` 时调用 `print_ticks()` 输出一行 `100 ticks`；
  - 使用静态局部变量 `printed_times` 统计打印次数，当达到 10 次后调用 `sbi_shutdown()` 关机（在未定义 `DEBUG_GRADE` 时有效）。

#### 验证方法

- 执行：

```bash
make -C lab4 clean
make -C lab4
make -C lab4 qemu
```

- 在串口输出中可观察到：
  - 物理内存信息与默认管理器名称输出；
  - `check_alloc_page() succeeded!` 等物理内存自检信息；
  - 每约 1 秒一次的 `100 ticks` 打印，以及在非 `DEBUG_GRADE` 模式下累计 10 次后自动关机。

---

### 练习1：分配并初始化一个进程控制块（需要编码）

#### 代码位置

- 文件：`kern/process/proc.c`  
- 函数：`static struct proc_struct *alloc_proc(void)`

#### 设计与实现

`alloc_proc`可以分配一块`proc_struct`并做最小可用初始化，让上层代码可以安全地把这个PCB挂入调度系统。

先使用 `kmalloc(sizeof(struct proc_struct))` 申请一块内核堆内存；若失败则返回 `NULL`。
再对关键字段进行显式初始化：
  - `state = PROC_UNINIT`：进程尚未进入就绪队列；
  - `pid = -1`：尚未分配合法 PID
  - `runs = 0`：尚未被调度运行
  - `kstack = 0`：尚未分配内核栈
  - `need_resched = 0`：初始不要求重新调度
  - `parent = NULL`：还没有确定父进程
  - `mm = NULL`：内核线程
  - `memset(&context, 0, sizeof(struct context))`：清零上下文，保证初始状态可预测
  - `tf = NULL`：当前没有挂接任何 trapframe
  - `pgdir = boot_pgdir_pa`：默认指向内核启动页表（内核线程共享同一页表）
  - `flags = 0`：清空进程标志位
  - `memset(name, 0, sizeof(name))`：清空进程名，由 `set_proc_name`设置
  - 使用 `list_init` 初始化 `list_link` 和 `hash_link`，确保插入全局链表和哈希表前处于干净状态。

这样的初始化方式可以与 `proc_init` 中的自检代码对齐，便于快速发现实现错误。

#### 问题回答：`context` 与 `tf` 的含义及作用

- `struct context`
  用于进程级上下文切换的最小寄存器集合。
    - `switch.S` 的 `switch_to(from, to)` 会把这几个寄存器从 `from->context` 保存、再从 `to->context` 恢复；
    - `proc_run` 在同一个内核中切换当前执行线程时，只需保存/恢复这些寄存器即可回到各自的内核栈和执行流；
    - 对于新 fork 出来的线程，`copy_thread` 会设置 `context.ra = forkret`、`context.sp = tf`，从而保证第一次被调度时能从 `forkret -> forkrets -> trap` 的正常入口进入。

- `struct trapframe *tf`含指向保存在内核栈上的完整 trapframe（`struct trapframe`），包含所有通用寄存器和CSR，即`status/epc/badvaddr/cause`。
    - 对于由 `kernel_thread`/`do_fork` 创建的内核线程，`copy_thread` 会把父进程传入的临时 `tf` 拷贝到子进程内核栈顶，`proc->tf` 指向这块区域；
    - 后续当发生中断，异常，或从 `forkret` 初次返回时，trap代码会使用 `current->tf` 作为恢复和修改的上下文载体，是从硬件角度看的。


### 练习2：为新创建的内核线程分配资源（需要编码）

#### 代码位置

- 文件：`kern/process/proc.c`  
- 函数：`int do_fork(uint32_t clone_flags, uintptr_t stack, struct trapframe *tf)`

#### 设计与实现步骤

`do_fork` 的作用是复制当前内核线程，主要针对内核线程`current->mm == NULL`的场景。实现流程如下：

1. **资源上限检查**  
   - 若`nr_process >= MAX_PROCESS`，直接返回`-E_NO_FREE_PROC`。

2. **分配进程控制块**  
   - 调用`alloc_proc()`，若返回`NULL`，则返回`-E_NO_MEM`。
   - 提前设置 `proc->parent = current`，便于后续回收与 wait。

3. **为子进程分配内核栈**  
   - 调用`setup_kstack(proc)`，内部使用`alloc_pages(KSTACKPAGE)` 分配若干物理页并映射为内核栈；
   - 若失败则跳转到`bad_fork_cleanup_proc`，释放PCB。

4. **复制/共享内存管理信息**  
   - 调用`copy_mm(clone_flags, proc)`，对内核线程场景执行 `assert(current->mm == NULL)`并返回 0，即不变更mm，子进程与父进程共享同一内核地址空间与`pgdir`。因为这里不需要真的复制共享`mm`，用户态才需要。
  

5. **复制寄存器状态与内核入口**  
   - 调用 `copy_thread(proc, stack, tf)`：
     - 在子进程内核栈顶构造一份 trapframe，并复制 `*tf`；
     - 将 `a0` 清零，以便子线程从 syscall/fork 语义上看到返回值为 0；
     - 设置 `proc->context.ra = forkret`、`proc->context.sp = proc->tf`，使得首次被调度执行时从 `forkret` 进入 C 代码。

6. **分配唯一PID并挂入全局结构**  
   - 调用`get_pid()`获取一个目前未被使用的PID，赋给`proc->pid`；
   - `hash_proc(proc)`：根据 `pid_hashfn` 将进程挂入 `hash_list` 中，便于 查找；
   - `list_add(&proc_list, &(proc->list_link))`：挂入双向链表 `proc_list`，作为调度遍历的基础；
   - `nr_process++`：全局进程计数加一。

7. **进入新进程并返回PID**  
   - 调用 `wakeup_proc(proc)` 将 `state`置为`PROC_RUNNABLE`；
   - 返回`ret = proc->pid`作为`do_fork`的返回值。

若在任一步骤中失败，则通过 `bad_fork_cleanup_kstack`和`bad_fork_cleanup_proc` 标签按顺序释放已分配的内核栈与 PCB，避免资源泄漏。

#### 问题回答：ucore是否做到为每个新fork的线程分配唯一ID？

回答：是的，ucore 为每个新fork的线程分配了全局唯一的PID。理由如下：

- `get_pid`使用静态变量`last_pid`和`next_safe`：
  - 每次从 `last_pid+1` 开始尝试分配，范围在 `[1, MAX_PID)`；
  - 遍历整个 `proc_list`，若发现有进程使用了当前 `last_pid`，则继续递增，必要时回绕到 1；
  - 同时维护 `next_safe` 为当前活动进程 PID 中大于 `last_pid` 的最小值，用于剪枝、减少遍历次数；
  - 只有当遍历完所有进程且没有发现冲突时才返回该 PID。
- 由于所有活跃进程都会挂入 `proc_list`，且 PID 选择过程中显式检查并跳过已存在的 PID，因此对于存活进程集合而言 PID 始终唯一。
- 结合 `MAX_PID > MAX_PROCESS` 的静态断言，可以保证在进程数上限内总能找到可用 PID，避免无限循环。

---

### 练习3：编写 `proc_run` 函数（需要编码）

#### 代码位置

- 文件：`kern/process/proc.c`  
- 函数：`void proc_run(struct proc_struct *proc)`

#### 设计与实现步骤

`proc_run`的作用是在 CPU 上切换当前运行的进程，与调度器`schedule`协同工作。实现步骤：

1. **自身份额外检查**
   - 若 `proc == current`，说明无需切换，直接返回。

2. **关中断，防止竞态**
   - 使用 `local_intr_save(intr_flag)` 通过 `__intr_save` 检查 `sstatus` 的 `SIE` 位：
     - 若原本开中断，则调用 `intr_disable()` 关闭中断并返回 `true`；
     - 若原本关中断，则直接返回 `false`。

3. **更新当前进程并切换页表**
   - 保存当前进程指针 `prev = current`，然后设置 `current = proc`；
   - 根据是否有独立地址空间选择页表：
     - 若 `current->mm != NULL`，则使用 `current->pgdir`；
     - 否则使用 `boot_pgdir_pa`；
   - 调用`lsatp(pgdir)`更新`satp`寄存器，使得后续访存走新进程的页表。

4. **调用`switch_to`切换上下文**
   - `switch_to(&(prev->context), &(current->context))`在汇编中将 `ra/sp/s0..s11`保存到`prev->context`，再从 `current->context` 加载对应寄存器，最终以 `ret` 指令返回到新进程上下文中记录的 `ra`，其中初次为 `forkret`。

5. **按原状态恢复中断**
   - 调用 `local_intr_restore(intr_flag)`，若 `intr_flag == true`，调用 `intr_enable()` 重新打开中断，若为 `false`，保持关中断状态不变。

#### 问题回答：本实验执行过程中创建并运行了几个内核线程？

- 第一个内核线程：`idleproc`
  - 由 `proc_init` 中直接调用`alloc_proc`和手工初始化创建；
  - PID 为 0，负责在系统空闲时调用`schedule()`。
- 第二个内核线程：`initproc`
  - 通过 `kernel_thread(init_main, "Hello world!!", 0)` 调用 `do_fork` 创建。
  - PID 由`get_pid`分配为 1。
  - 在`init_main`中打印若干行调试输出后返回。

因此，本实验中创建并运行了2个内核线程：`idleproc` 和 `initproc`。

---

### 扩展练习 Challenge：`local_intr_save/restore` 如何实现开关中断？

#### 宏与实现代码

- 宏定义（`kern/sync/sync.h`）：

```c
#define local_intr_save(x) \
    do {                   \
        x = __intr_save(); \
    } while (0)
#define local_intr_restore(x) __intr_restore(x);
```

- 内部函数：

```c
static inline bool __intr_save(void) {
    if (read_csr(sstatus) & SSTATUS_SIE) {
        intr_disable();
        return 1;
    }
    return 0;
}

static inline void __intr_restore(bool flag) {
    if (flag) {
        intr_enable();
    }
}
```

#### 工作机制说明

- `local_intr_save(intr_flag)`：
  - 读取 `sstatus` CSR，检查 `SSTATUS_SIE` 位是否为 1（当前是否允许中断）；
  - 若为 1，则调用 `intr_disable()` 清除 `SIE` 位，关闭中断，并返回 `true`；
  - 若为 0，则不做任何修改，返回 `false`；
  - 因此，`intr_flag` 记录下 “进入临界区之前是否是开中断状态”。

- `local_intr_restore(intr_flag)`：
  - 若 `intr_flag == true`，则调用 `intr_enable()` 设置 `SIE` 位，恢复到开中断状态；
  - 若 `intr_flag == false`，则保持当前状态（继续关中断），不做任何修改。

这种封装方式的好处是，代码片段对调用点原先的中断状态透明，不会把原本关中断的上下文误地打开，且支持在嵌套调用场景下安全使用，只要每个临界区都用自己的 `intr_flag` 变量记录状态即可。


### 深入理解不同分页模式与 `get_pte` 的工作原理（思考题）

#### 问题 1：`get_pte` 中两段相似代码的原因

`get_pte` 实现如下（节选）：

```c
pte_t *get_pte(pde_t *pgdir, uintptr_t la, bool create)
{
    pde_t *pdep1 = &pgdir[PDX1(la)];
    if (!(*pdep1 & PTE_V)) {
        struct Page *page;
        if (!create || (page = alloc_page()) == NULL) {
            return NULL;
        }
        set_page_ref(page, 1);
        uintptr_t pa = page2pa(page);
        memset(KADDR(pa), 0, PGSIZE);
        *pdep1 = pte_create(page2ppn(page), PTE_U | PTE_V);
    }
    pde_t *pdep0 = &((pte_t *)KADDR(PDE_ADDR(*pdep1)))[PDX0(la)];
    if (!(*pdep0 & PTE_V)) {
        struct Page *page;
        if (!create || (page = alloc_page()) == NULL) {
            return NULL;
        }
        set_page_ref(page, 1);
        uintptr_t pa = page2pa(page);
        memset(KADDR(pa), 0, PGSIZE);
        *pdep0 = pte_create(page2ppn(page), PTE_U | PTE_V);
    }
    return &((pte_t *)KADDR(PDE_ADDR(*pdep0)))[PTX(la)];
}
```

- RISC-V 的多级页表本质上是重复同一层级操作：
  - 给定线性地址 `la`，不断用高位若干 bit 作为索引，查找对应页目录项；
  - 若目录项无效且 `create == true`，则分配一个新的页表页并清零；
  - 将页表页的物理地址写入目录项，再进入下一层。
- Sv32 使用 2 级页表，包含根表+次级表，因此在ucore当前实现中对应两段几乎一模一样的代码：第一次处理 `pdep1`，第二次处理 `pdep0`；
- Sv39、Sv48 则在此基础上增加更多层级，每一级的处理模式完全相同，只是用不同的宏，如`PX(level, la)`取不同比特范围作为索引；
这两段代码看起来相似，是因为它们就是第1级页目录遍历和第0级页目录遍历的模式复制，对应不同分页模式时只需扩展和压缩层数即可。

#### 问题 2：`get_pte` 同时做“查找”和“分配”是否合适？要不要拆分？

当前`get_pte`在一次函数调用中既负责查找页表项，又在需要时分配中间页表页。这种设计的优点有：
  - 调用方非常简单：只需调用一次 `get_pte(pgdir, la, create)`，即可得到可写的 `pte_t *`；
  - 对于内核映射、用户空间映射等常见场景，逻辑高度一致，避免在各处重复写 “如果缺页就分配并清零” 的样板代码；
  - 有利于在修改多级页表结构时，将实现细节封装在一个地方。

缺点有：
  - 在查一下映射是否存在的场景下，如权限检查也必须小心传入`create=false`，否则会意外修改页表；
  - 不利于做更复杂的策略，例如先dry-run看看路径上缺失了几级，再一次性批量分配并统计成本。

**是否有必要拆分？**

从工程角度考虑，很多内核也采用类似的遍历 + 可选分配组合接口，便于调用。可以将当前`get_pte`视为高层封装，再抽出一个只读版本，只做查找、不做分配，用于调试/检查场景。当前场景下不拆分也是可行的。
