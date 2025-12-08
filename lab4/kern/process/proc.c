#include <proc.h>
#include <kmalloc.h>
#include <string.h>
#include <sync.h>
#include <pmm.h>
#include <error.h>
#include <sched.h>
#include <elf.h>
#include <vmm.h>
#include <trap.h>
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

/* ------------- 进程/线程机制设计与实现 -------------
（一个简化的 Linux 进程/线程机制）
介绍：
  ucore 实现了一个简单的进程/线程机制。进程包含独立的内存空间，至少一个用于执行的线程，
内核数据（用于管理），处理器状态（用于上下文切换），文件（在 lab6 中）等。ucore 需要
高效地管理所有这些细节。在 ucore 中，线程只是一种特殊的进程（共享进程的内存）。
------------------------------
进程状态       :     含义               -- 原因
    PROC_UNINIT     :   未初始化           -- alloc_proc
    PROC_SLEEPING   :   睡眠中                -- try_free_pages, do_wait, do_sleep
    PROC_RUNNABLE   :   可运行（可能正在运行） -- proc_init, wakeup_proc,
    PROC_ZOMBIE     :   几乎死亡             -- do_exit

-----------------------------
进程状态转换：

  alloc_proc                                 运行中
      +                                   +--<----<--+
      +                                   + proc_run +
      V                                   +-->---->--+
PROC_UNINIT -- proc_init/wakeup_proc --> PROC_RUNNABLE -- try_free_pages/do_wait/do_sleep --> PROC_SLEEPING --
                                           A      +                                                           +
                                           |      +--- do_exit --> PROC_ZOMBIE                                +
                                           +                                                                  +
                                           -----------------------wakeup_proc----------------------------------
-----------------------------
进程关系
父进程:           proc->parent  (proc 是子进程)
子进程:           proc->cptr    (proc 是父进程)
年长兄弟:         proc->optr    (proc 是年幼兄弟)
年幼兄弟:         proc->yptr    (proc 是年长兄弟)
-----------------------------
进程相关的系统调用：
SYS_exit        : 进程退出,                           -->do_exit
SYS_fork        : 创建子进程, 复制内存空间            -->do_fork-->wakeup_proc
SYS_wait        : 等待进程                            -->do_wait
SYS_exec        : fork 后, 进程执行程序   -->加载程序并刷新内存空间
SYS_clone       : 创建子线程                     -->do_fork-->wakeup_proc
SYS_yield       : 进程标记自己需要重新调度, -- proc->need_sched=1, 然后调度器会重新调度此进程
SYS_sleep       : 进程睡眠                           -->do_sleep
SYS_kill        : 杀死进程                            -->do_kill-->proc->flags |= PF_EXITING
                                                                 -->wakeup_proc-->do_wait-->do_exit
SYS_getpid      : 获取进程的 pid

*/

// 进程集合的列表
list_entry_t proc_list;

#define HASH_SHIFT 10
#define HASH_LIST_SIZE (1 << HASH_SHIFT)
#define pid_hashfn(x) (hash32(x, HASH_SHIFT))

// 基于 pid 的进程集合哈希列表
static list_entry_t hash_list[HASH_LIST_SIZE];

// 空闲进程
struct proc_struct *idleproc = NULL;
// 初始化进程
struct proc_struct *initproc = NULL;
// 当前进程
struct proc_struct *current = NULL;

static int nr_process = 0;

void kernel_thread_entry(void);
void forkrets(struct trapframe *tf);
void switch_to(struct context *from, struct context *to);

// alloc_proc - 分配并初始化 proc_struct 的所有字段
static struct proc_struct *
alloc_proc(void)
{
    struct proc_struct *proc = kmalloc(sizeof(struct proc_struct));
    if (proc != NULL)
    {
        // 初始状态全部清零，表示尚未放入调度系统
        proc->state = PROC_UNINIT;
        proc->pid = -1;
        proc->runs = 0;
        proc->kstack = 0;
        proc->need_resched = 0;
        proc->parent = NULL;
        proc->mm = NULL;
        memset(&(proc->context), 0, sizeof(struct context));
        proc->tf = NULL;
        proc->pgdir = boot_pgdir_pa; // 默认使用内核页表，后续可根据需要替换
        proc->flags = 0;
        memset(proc->name, 0, sizeof(proc->name));
        list_init(&(proc->list_link));
        list_init(&(proc->hash_link));
    }
    return proc;
}

// set_proc_name - 设置进程名称
char *
set_proc_name(struct proc_struct *proc, const char *name)
{
    memset(proc->name, 0, sizeof(proc->name));
    return memcpy(proc->name, name, PROC_NAME_LEN);
}

// get_proc_name - 获取进程名称
char *
get_proc_name(struct proc_struct *proc)
{
    static char name[PROC_NAME_LEN + 1];
    memset(name, 0, sizeof(name));
    return memcpy(name, proc->name, PROC_NAME_LEN);
}

// get_pid - 为进程分配唯一的 pid
static int
get_pid(void)
{
    static_assert(MAX_PID > MAX_PROCESS);
    struct proc_struct *proc;
    list_entry_t *list = &proc_list, *le;
    static int next_safe = MAX_PID, last_pid = MAX_PID;
    if (++last_pid >= MAX_PID)
    {
        last_pid = 1;
        goto inside;
    }
    if (last_pid >= next_safe)
    {
    inside:
        next_safe = MAX_PID;
    repeat:
        le = list;
        while ((le = list_next(le)) != list)
        {
            proc = le2proc(le, list_link);
            if (proc->pid == last_pid)
            {
                if (++last_pid >= next_safe)
                {
                    if (last_pid >= MAX_PID)
                    {
                        last_pid = 1;
                    }
                    next_safe = MAX_PID;
                    goto repeat;
                }
            }
            else if (proc->pid > last_pid && next_safe > proc->pid)
            {
                next_safe = proc->pid;
            }
        }
    }
    return last_pid;
}

// proc_run - 使进程 "proc" 在 CPU 上运行
// 注意：在调用 switch_to 之前，应该加载 "proc" 新页表的基地址
void proc_run(struct proc_struct *proc)
{
    if (proc != current)
    {
        bool intr_flag;
        struct proc_struct *prev = current;
        local_intr_save(intr_flag);
        {
            current = proc;             // 更新当前进程
            lsatp(proc->pgdir);         // 切换到目标进程的页表
            switch_to(&(prev->context), &(proc->context)); // 保存/恢复上下文
        }
        local_intr_restore(intr_flag);
    }
}

// forkret -- 新线程/进程的第一个内核入口点
// 注意：forkret 的地址在 copy_thread 函数中设置
//       switch_to 之后，当前进程将在这里执行。
static void
forkret(void)
{
    forkrets(current->tf);
}

// hash_proc - 将进程添加到进程哈希列表中
static void
hash_proc(struct proc_struct *proc)
{
    list_add(hash_list + pid_hashfn(proc->pid), &(proc->hash_link));
}

// find_proc - 根据 pid 从进程哈希列表中查找进程
struct proc_struct *
find_proc(int pid)
{
    if (0 < pid && pid < MAX_PID)
    {
        list_entry_t *list = hash_list + pid_hashfn(pid), *le = list;
        while ((le = list_next(le)) != list)
        {
            struct proc_struct *proc = le2proc(le, hash_link);
            if (proc->pid == pid)
            {
                return proc;
            }
        }
    }
    return NULL;
}

// kernel_thread - 使用 "fn" 函数创建内核线程
// 注意：临时 trapframe tf 的内容将被复制到
//       do_fork-->copy_thread 函数中的 proc->tf
int kernel_thread(int (*fn)(void *), void *arg, uint32_t clone_flags)
{
    struct trapframe tf;
    memset(&tf, 0, sizeof(struct trapframe));
    tf.gpr.s0 = (uintptr_t)fn;
    tf.gpr.s1 = (uintptr_t)arg;
    tf.status = (read_csr(sstatus) | SSTATUS_SPP | SSTATUS_SPIE) & ~SSTATUS_SIE;
    tf.epc = (uintptr_t)kernel_thread_entry;
    return do_fork(clone_flags | CLONE_VM, 0, &tf);
}

// setup_kstack - 分配大小为 KSTACKPAGE 的页作为进程内核栈
static int
setup_kstack(struct proc_struct *proc)
{
    struct Page *page = alloc_pages(KSTACKPAGE);
    if (page != NULL)
    {
        proc->kstack = (uintptr_t)page2kva(page);
        return 0;
    }
    return -E_NO_MEM;
}

// put_kstack - 释放进程内核栈的内存空间
static void
put_kstack(struct proc_struct *proc)
{
    free_pages(kva2page((void *)(proc->kstack)), KSTACKPAGE);
}

// copy_mm - 根据 clone_flags 复制或共享当前进程 "current" 的内存空间给进程 "proc"
//         - 如果 clone_flags & CLONE_VM，则"共享"；否则"复制"
static int
copy_mm(uint32_t clone_flags, struct proc_struct *proc)
{
    assert(current->mm == NULL);
    /* do nothing in this project */
    return 0;
}

// copy_thread - 在进程内核栈顶设置 trapframe 并
//             - 设置进程的内核入口点和栈
static void
copy_thread(struct proc_struct *proc, uintptr_t esp, struct trapframe *tf)
{
    proc->tf = (struct trapframe *)(proc->kstack + KSTACKSIZE - sizeof(struct trapframe));
    *(proc->tf) = *tf;

    // 将 a0 设置为 0，以便子进程知道它刚刚被 fork
    proc->tf->gpr.a0 = 0;
    proc->tf->gpr.sp = (esp == 0) ? (uintptr_t)proc->tf : esp;

    proc->context.ra = (uintptr_t)forkret;
    proc->context.sp = (uintptr_t)(proc->tf);
}

/* do_fork -     parent process for a new child process
 * @clone_flags: used to guide how to clone the child process
 * @stack:       the parent's user stack pointer. if stack==0, It means to fork a kernel thread.
 * @tf:          the trapframe info, which will be copied to child process's proc->tf
 */
int do_fork(uint32_t clone_flags, uintptr_t stack, struct trapframe *tf)
{
    int ret = -E_NO_FREE_PROC;
    struct proc_struct *proc;
    if (nr_process >= MAX_PROCESS)
    {
        goto fork_out;
    }
    ret = -E_NO_MEM;
    if ((proc = alloc_proc()) == NULL)
    {
        goto fork_out;
    }

    proc->parent = current; // 记录父进程，便于回收/等待

    if ((ret = setup_kstack(proc)) != 0)
    {
        goto bad_fork_cleanup_proc;
    }

    if ((ret = copy_mm(clone_flags, proc)) != 0)
    {
        goto bad_fork_cleanup_kstack;
    }

    copy_thread(proc, stack, tf); // 复制寄存器及返回点，构造初始上下文

    proc->pid = get_pid();                       // 分配全局唯一PID
    hash_proc(proc);                             // 加入PID哈希表便于查找
    list_add(&proc_list, &(proc->list_link));    // 加入全局进程链表
    nr_process++;
    wakeup_proc(proc);                           // 设置为可调度状态
    ret = proc->pid;

fork_out:
    return ret;

bad_fork_cleanup_kstack:
    put_kstack(proc);
bad_fork_cleanup_proc:
    kfree(proc);
    goto fork_out;
}

// do_exit - 被 sys_exit 调用
//   1. 调用 exit_mmap & put_pgdir & mm_destroy 来释放进程的几乎所有内存空间
//   2. 将进程状态设置为 PROC_ZOMBIE，然后调用 wakeup_proc(parent) 来让父进程回收自己。
//   3. 调用调度器切换到其他进程
int do_exit(int error_code)
{
    panic("process exit!!.\n");
}

// init_main - 第二个内核线程，用于创建 user_main 内核线程
static int
init_main(void *arg)
{
    cprintf("this initproc, pid = %d, name = \"%s\"\n", current->pid, get_proc_name(current));
    cprintf("To U: \"%s\".\n", (const char *)arg);
    cprintf("To U: \"en.., Bye, Bye. :)\"\n");
    return 0;
}

// proc_init - 自行设置第一个内核线程 idleproc "idle" 并
//           - 创建第二个内核线程 init_main
void proc_init(void)
{
    int i;

    list_init(&proc_list);
    for (i = 0; i < HASH_LIST_SIZE; i++)
    {
        list_init(hash_list + i);
    }

    if ((idleproc = alloc_proc()) == NULL)
    {
        panic("cannot alloc idleproc.\n");
    }

    // 检查进程结构体
    int *context_mem = (int *)kmalloc(sizeof(struct context));
    memset(context_mem, 0, sizeof(struct context));
    int context_init_flag = memcmp(&(idleproc->context), context_mem, sizeof(struct context));

    int *proc_name_mem = (int *)kmalloc(PROC_NAME_LEN);
    memset(proc_name_mem, 0, PROC_NAME_LEN);
    int proc_name_flag = memcmp(&(idleproc->name), proc_name_mem, PROC_NAME_LEN);

    if (idleproc->pgdir == boot_pgdir_pa && idleproc->tf == NULL && !context_init_flag && idleproc->state == PROC_UNINIT && idleproc->pid == -1 && idleproc->runs == 0 && idleproc->kstack == 0 && idleproc->need_resched == 0 && idleproc->parent == NULL && idleproc->mm == NULL && idleproc->flags == 0 && !proc_name_flag)
    {
        cprintf("alloc_proc() correct!\n");
    }

    idleproc->pid = 0;
    idleproc->state = PROC_RUNNABLE;
    idleproc->kstack = (uintptr_t)bootstack;
    idleproc->need_resched = 1;
    set_proc_name(idleproc, "idle");
    nr_process++;

    current = idleproc;

    int pid = kernel_thread(init_main, "Hello world!!", 0);
    if (pid <= 0)
    {
        panic("create init_main failed.\n");
    }

    initproc = find_proc(pid);
    set_proc_name(initproc, "init");

    assert(idleproc != NULL && idleproc->pid == 0);
    assert(initproc != NULL && initproc->pid == 1);
}

// cpu_idle - 在 kern_init 结束时，第一个内核线程 idleproc 将执行以下工作
void cpu_idle(void)
{
    while (1)
    {
        if (current->need_resched)
        {
            schedule();
        }
    }
}
