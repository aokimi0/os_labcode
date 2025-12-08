#ifndef __KERN_PROCESS_PROC_H__
#define __KERN_PROCESS_PROC_H__

#include <defs.h>
#include <list.h>
#include <trap.h>
#include <memlayout.h>

// 进程在其生命周期中的状态
enum proc_state
{
    PROC_UNINIT = 0, // 未初始化
    PROC_SLEEPING,   // 睡眠中
    PROC_RUNNABLE,   // 可运行（可能正在运行）
    PROC_ZOMBIE,     // 几乎死亡，等待父进程回收其资源
};

struct context
{
    uintptr_t ra;
    uintptr_t sp;
    uintptr_t s0;
    uintptr_t s1;
    uintptr_t s2;
    uintptr_t s3;
    uintptr_t s4;
    uintptr_t s5;
    uintptr_t s6;
    uintptr_t s7;
    uintptr_t s8;
    uintptr_t s9;
    uintptr_t s10;
    uintptr_t s11;
};

#define PROC_NAME_LEN 15
#define MAX_PROCESS 4096
#define MAX_PID (MAX_PROCESS * 2)

extern list_entry_t proc_list;

struct proc_struct
{
    enum proc_state state;        // 进程状态
    int pid;                      // 进程ID
    int runs;                     // 进程的运行次数
    uintptr_t kstack;             // 进程内核栈
    volatile bool need_resched;   // 布尔值：需要重新调度以释放CPU？
    struct proc_struct *parent;   // 父进程
    struct mm_struct *mm;         // 进程的内存管理字段
    struct context context;       // 切换到这里运行进程
    struct trapframe *tf;         // 当前中断的陷阱帧
    uintptr_t pgdir;              // 页目录表(PDT)的基地址
    uint32_t flags;               // 进程标志
    char name[PROC_NAME_LEN + 1]; // 进程名
    list_entry_t list_link;       // 进程链表
    list_entry_t hash_link;       // 进程哈希列表
};

#define le2proc(le, member) \
    to_struct((le), struct proc_struct, member)

extern struct proc_struct *idleproc, *initproc, *current;

void proc_init(void);
void proc_run(struct proc_struct *proc);
int kernel_thread(int (*fn)(void *), void *arg, uint32_t clone_flags);

char *set_proc_name(struct proc_struct *proc, const char *name);
char *get_proc_name(struct proc_struct *proc);
void cpu_idle(void) __attribute__((noreturn));

struct proc_struct *find_proc(int pid);
int do_fork(uint32_t clone_flags, uintptr_t stack, struct trapframe *tf);
int do_exit(int error_code);

#endif /* !__KERN_PROCESS_PROC_H__ */
