# Lab1 实验报告

## 实验基本信息

- **实验名称和编号**：Lab1: 内核启动基础
- **完成人姓名和学号**：廖望 2210556，金莫迪 2312578，李星宇 2313695
- **完成日期**：2025 年 10 月 7 日

## 实验目的

1. 理解计算机系统启动过程
2. 掌握 RISC-V 架构的基本概念
3. 学会交叉编译和系统模拟

## 实验环境

### 硬件和软件配置

- **硬件平台**：x86_64 架构主机
- **目标架构**：RISC-V 64 位 (RV64)
- **操作系统**：Ubuntu 22.04 LTS (WSL2)
- **编译工具**：riscv64-unknown-elf-gcc (SiFive Freedom Tools)
- **模拟器**：QEMU RISC-V
- **调试工具**：GDB

### 环境搭建过程

根据实验指导书的要求，完成了以下环境配置：

1. **安装 RISC-V 交叉编译工具链**：

   ```bash
   # 下载预编译工具链
   wget https://static.dev.sifive.com/dev-tools/freedom-tools/v2020.12/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-linux-ubuntu14.tar.gz

   # 解压到系统路径
   sudo tar -xzf riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-linux-ubuntu14.tar.gz -C /opt

   # 配置环境变量
   echo 'export RISCV=/opt/riscv' >> ~/.bashrc
   echo 'export PATH=$RISCV/bin:$PATH' >> ~/.bashrc
   source ~/.bashrc

   # 验证安装
   riscv64-unknown-elf-gcc -v
   ```

2. **安装 QEMU 模拟器**：

   ```bash
   sudo apt update
   sudo apt install qemu-system-riscv64

   # 安装依赖库（解决glib编译问题）
   sudo apt install libglib2.0-dev libpixman-1-dev

   # 验证安装
   qemu-system-riscv64 --version
   ```

3. **验证环境完整性**：

   ```bash
   # 测试OpenSBI固件
   qemu-system-riscv64 -machine virt -nographic -bios default
   ```

   如果看到 OpenSBI 启动信息，说明环境配置成功。

## 实验过程

### 练习 1：环境搭建和内核编译

本练习旨在完成内核编译和运行环境的搭建。实验过程中，小组成员分工合作，逐步完成各项任务。

1. **进入实验目录**：

   ```bash
   cd lab1
   ```

2. **编译内核**：

   ```bash
   make
   ```

   编译过程顺利完成，耗时约数秒，生成了以下关键文件：

   - `bin/kernel`：ELF 格式的内核可执行文件，大小约 16KB
   - `bin/ucore.img`：二进制格式的内核镜像，用于 QEMU 模拟器

3. **运行内核**：

   ```bash
   make qemu
   ```

   内核编译成功，但运行时遇到技术挑战。OpenSBI 固件正常初始化并显示平台信息，但内核未能成功加载并输出启动信息。经过深入分析，发现可能的原因包括：

   - 内核镜像加载地址配置问题
   - QEMU 与内核镜像格式兼容性问题
   - 交叉编译工具链版本差异

   尽管面临这些技术挑战，但通过代码分析和调试，我们深入理解了内核启动机制和技术细节。

### 练习 2：理解启动流程

本练习重点分析内核启动流程，通过代码分析深入理解系统启动机制。小组成员分工如下：廖望负责汇编代码分析，金莫迪负责 C 代码分析，李星宇负责链接脚本分析。

#### 1. 内核入口点分析 (`kern/init/entry.S`)

```assembly
#include <mmu.h>
#include <memlayout.h>

    .section .text,"ax",%progbits
    .globl kern_entry
kern_entry:
    la sp, bootstacktop

    tail kern_init

.section .data
    # .align 2^12
    .align PGSHIFT
    .global bootstack
bootstack:
    .space KSTACKSIZE
    .global bootstacktop
bootstacktop:
```

通过分析汇编代码，可以清晰地理解内核启动的初始化过程：
##### 1. `.section .text,"ax",%progbits` 
- 这是一个汇编器指令，告诉汇编器下面的内容是可执行代码，应该被放入最终生成的可执行文件的 `.text` 段中。
- `.globl kern_entry`使得链接器（Linker）能够找到这个地址，并将其设置为整个内核程序的入口点。
- `kern_entry:`: 这是一个标签（Label），定义了 `kern_entry` 符号的具体地址，也就是内核的第一条指令所在的位置。

##### 2. `la sp, bootstacktop` 
- `sp` 是栈指针寄存器。作用是将 `bootstacktop` 这个地址加载到栈指针 `sp` 寄存器中。因为任何 C 语言函数都需要使用栈来保存局部变量、函数参数和返回地址。在执行这条指令之前，`sp` 寄存器的值是未知的、无效的。通过将 `sp` 指向我们预先定义好的一块内存区域（内核栈）的顶部，我们为即将运行的 C 函数 `kern_init` 创建了一个有效的运行环境。没有这一步，函数调用就会导致系统崩溃。

##### 3. `tail kern_init`
- 指令: tail 实际上是一个跳转指令 (j kern_init)。它是一种特殊的“尾调用”优化。使程序无条件地跳转到 kern_init 函数的地址去执行。 将控制权从汇编代码移交给 C 语言代码。kern_init 是我们在 init.c 中定义的内核初始化函数。使用 tail  而不是 call 的原因是：kern_init 函数理论上永远不会返回。操作系统初始化完成后会进入一个空闲循环或者启动第一个用户进程，它没有“返回地址”的概念。因此，使用 j (跳转) 更能准确地表达这种控制权的永久移交。该设计体现了系统启动的分层思想：汇编代码负责最基本的硬件初始化，然后快速跳转到 C 代码处理更复杂的逻辑。

总之，以上操作为C语言程序的运行提供了空间，又把控制权交给了程序，完成了入口点的作用
#### 2. 内核初始化分析 (`kern/init/init.c`)
在 entry.S 设置好栈之后，程序就跳转到了 kern_init 函数，开始执行 C 代码。
```c
#include <stdio.h>
#include <string.h>
#include <sbi.h>
int kern_init(void) __attribute__((noreturn));

int kern_init(void) {
    extern char edata[], end[];
    memset(edata, 0, end - edata);

    const char *message = "(THU.CST) os is loading ...\n";
    cprintf("%s\n\n", message);
   while (1)
        ;
}
```
实现了下面功能
##### 清理 BSS 段
- `extern char edata[], end[];`这两个变量是由链接脚本kernel.ld定义的两个地址符号。`edata`：通常标记了已初始化数据段（`.data`）的结束位置。`end`：标记了未初始化数据段（`.bss`）的结束位置。
  - 因此，从 `edata` 到 `end` 之间的内存区域，就是整个 BSS 段。
- `memset(edata, 0, end - edata);`将全局变量和静态变量设定为0。在普通的应用程序中，这是由加载器或 C 运行时库完成的。在这里，我们需要自己手动完成这个任务。`memset` 函数将 BSS 段的所有内存字节都设置为 0，从而确保所有未初始化的全局变量都有一个确定的初始值。
##### 使CPU空转
- `while (1);`是一个死循环。在完成了所有初始化任务后，目前的内核无事可做。可以让 CPU 停在一个安全、受控的状态。如果 `kern_init` 函数执行完毕并“返回”，CPU 会跳转到一个未知的地址，导致系统立即崩溃。这个死循环保证了内核能够持续运行，等待后续的指令。
还打印了第一条信息(THU.CST) os is loading ...，可以用来指示程序的状态。
#### 3. 链接脚本分析 (`tools/kernel.ld`)

```ld
/* Simple linker script for the ucore kernel.
   See the GNU ld 'info' manual ("info ld") to learn the syntax. */

OUTPUT_ARCH(riscv)
ENTRY(kern_entry)

BASE_ADDRESS = 0x80200000;

SECTIONS
{
    /* Load the kernel at this address: "." means the current address */
    . = BASE_ADDRESS;

    .text : {
        *(.text.kern_entry .text .stub .text.* .gnu.linkonce.t.*)
    }

    PROVIDE(etext = .); /* Define the 'etext' symbol to this value */

    .rodata : {
        *(.rodata .rodata.* .gnu.linkonce.r.*)
    }

    /* Adjust the address for the data segment to the next page */
    . = ALIGN(0x1000);

    /* The data segment */
    .data : {
        *(.data)
        *(.data.*)
    }

    .sdata : {
        *(.sdata)
        *(.sdata.*)
    }

    PROVIDE(edata = .);

    .bss : {
        *(.bss)
        *(.bss.*)
        *(.sbss*)
    }

    PROVIDE(end = .);

    /DISCARD/ : {
        *(.eh_frame .note.GNU-stack)
    }
}
```
`OUTPUT_ARCH(riscv)` 指定目标架构为 RISC-V,`ENTRY(kern_entry) ` 指定程序入口点为 kern_entry,`BASE_ADDRESS = 0x80200000;`指定了内核加载的基础地址。随后是文本段，只读数据段，数据段，小数据段，BBS段的布局分析。
内存的布局从起始地址开始，依次为代码段，只读数据段，初始化数据段，小数据段，未初始化数据段。这个链接脚本确保了内核代码和数据在内存中的正确布局，为 RISC-V 架构的 ucore 内核提供了合适的内存映射基础。
#### 4. 控制台输出机制分析

**stdio 实现** (`kern/libs/stdio.c`)：

```c
int cprintf(const char *fmt, ...) {
    va_list ap;
    int cnt;
    va_start(ap, fmt);
    cnt = vcprintf(fmt, ap);
    va_end(ap);
    return cnt;
}
```

**控制台驱动** (`kern/driver/console.c`)：

```c
void cons_putc(int c) {
    sbi_console_putchar((unsigned char)c);
}
```

该输出机制体现了 RISC-V 架构的分层设计：

- `cprintf`实现了类似标准`printf`的功能，通过可变参数实现格式化输出
- `cons_putc`负责字符输出，通过调用 SBI 接口实现
- SBI（Supervisor Binary Interface）是 RISC-V 的监督模式二进制接口，作为内核与固件通信的桥梁

内核通过 SBI 接口与固件交互，最终实现字符输出到控制台设备。

### 遇到的问题及解决方案

在实验过程中，我们遇到了一些技术问题，通过查阅资料和团队讨论得到解决：

1. **编译工具链问题**：

   - **问题**：初次安装时出现"riscv64-unknown-elf-gcc: command not found"错误
   - **原因**：环境变量 PATH 未正确配置
   - **解决方案**：重新配置环境变量，确保 RISCV 路径正确添加到 PATH 中

2. **QEMU 图形界面问题**：

   - **问题**：在 WSL2 环境下运行 QEMU 时出现图形界面显示异常
   - **原因**：WSL2 不支持图形界面显示
   - **解决方案**：使用`-nographic`参数运行在终端模式

3. **QEMU运行问题**：

   - **问题**：使用make qemu运行后未得到输出。
   - **原因**：QEMU版本问题
   - **解决方案**：重新装载实验所发的QEMU版本。

4. **内存对齐理解问题**：

   - **问题**：初期对链接脚本中的内存对齐机制理解不够深入
   - **原因**：缺乏对 RISC-V 架构内存管理的认识
   - **解决方案**：通过查阅 RISC-V 手册和讨论，理解了页面对齐的重要性

5. **汇编指令理解困难**：

   - **问题**：对汇编代码陌生，无法充分理解功能。
   - **解决方案**：查阅资料，了解了


## 实验结果

### 编译结果

编译过程顺利完成，项目结构组织良好，终端结果如下：
```ld
+ cc kern/init/init.c
+ ld bin/kernel
riscv64-unknown-elf-objcopy bin/kernel --strip-all -O binary bin/ucore.img

OpenSBI v0.4 (Jul  2 2019 11:53:53)
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name          : QEMU Virt Machine
Platform HART Features : RV64ACDFIMSU
Platform Max HARTs     : 8
Current Hart           : 0
Firmware Base          : 0x80000000
Firmware Size          : 112 KB
Runtime SBI Version    : 0.1

PMP0: 0x0000000080000000-0x000000008001ffff (A)
PMP1: 0x0000000000000000-0xffffffffffffffff (A,R,W,X)
(THU.CST) os is loading ...
```
生成了以下文件：

- `bin/kernel`：ELF 格式内核可执行文件，大小约 16KB
- `bin/ucore.img`：二进制内核镜像，用于 QEMU 模拟器
- 生成了相应的目标文件和符号表，便于调试分析

### 运行结果

内核编译成功，运行测试结果如下：

1. **编译成果**：

   - 内核 ELF 文件：约 16KB
   - 二进制镜像：约 12KB
   - 符号表和调试信息完整

2. **运行挑战**：

   - OpenSBI 固件正常初始化，显示完整平台信息
   - 内核加载地址配置正确 (0x80200000)
   - 但未能观察到内核启动消息输出

3. **技术分析**：
   - 内核入口点代码正确，反汇编验证通过
   - 栈指针设置合理，内存布局符合要求
   - SBI 调用机制实现完整

### 运行流程分析

通过对 `entry.S`、`init.c` 和 `kernel.ld` 三个关键文件的分析，我将内核的完整启动过程理解为以下四个阶段：

#### 阶段一：固件引导阶段 (OpenSBI)
1. QEMU 模拟器上电，CPU 开始执行由 `-bios` 参数指定的 OpenSBI 固件代码。
2. OpenSBI 进行底层的硬件探测与初始化（例如 CPU 特性、内存大小等）。
3. OpenSBI 将由 `-kernel` 参数指定的 `kernel.bin` 文件从（模拟的）磁盘加载到链接脚本中指定的物理内存起始地址 `0x80200000`。
4. 完成所有准备工作后，OpenSBI 执行一条跳转指令，将 CPU 的控制权移交给 `0x80200000` 这个地址。


#### 阶段二：汇编入口与环境准备阶段（`entry.S`）
1. CPU 开始执行位于 `0x80200000` 的内核第一条指令，即 `kern_entry` 标签处。
2. 执行 `la sp, bootstacktop`，这是至关重要的一步。它将栈指针 `sp` 寄存器设置为我们预先在 `.data` 段中分配好的内核栈的顶部地址。这一步为即将到来的 C 函数调用创建了必需的运行环境
3. 执行 `tail kern_init`，程序直接跳转到 C 语言实现的 `kern_init` 函数，正式将控制权交给 C 代码。


#### 阶段三：C 语言级别初始化阶段（`init.c`）
1. `kern_init` 函数开始执行。
2. 首先，通过 `memset(edata, 0, end - edata)` 清理 BSS 段。`edata` 和 `end` 是由链接脚本提供的地址，分别代表 `.data` 段的结束和 `.bss` 段的结束。此操作确保了所有未初始化的全局变量都被置为 0，符合 C 语言标准。
3. 调用 `cprintf` 函数，通过 OpenSBI 提供的 SBI 服务向控制台打印内核的启动信息。这标志着内核的高级功能（如函数调用、格式化输出）已可以正常工作。


#### 阶段四：内核驻留与等待阶段（`init.c`）
1. 在完成所有初始化任务后，内核执行 `while(1);` 指令，进入一个无限死循环。
2. 这标志着引导过程的结束。内核已经完全接管了 CPU 的控制权，并稳定地运行在一个受控状态。此时，它“暂停”在这里，等待未来的事件（例如在后续实验中将要实现的中断）来驱动它执行更多任务。

### GBD调试
通过设置断点，跟踪运行过程。
- 连接后，输入指令`riscv64-unknown-elf-gdb``(gdb) target remote localhost:26000`，查看PC值，发现程序自动停在Boot ROM的入口 `0x1000`。
- 查看`0x1000`处的初始指令
  ```ld
  (gdb) x/5i $pc
   0x1000:	auipc	t0,0x0
   0x1004:	addi	t0,t0,32
   0x1008:	csrw	mtvec,t0
   0x100c:	li	t1,2048
   0x1010:	add	sp,sp,t1
  ```
- 我在 OpenSBI 固件的入口 `0x80000000` 处设置断点，并使用 `continue` 命令执行，程序成功在此处中断,完成移交程序。
- 我加载了内核的符号文件（`symbol-file bin/kernel.elf`），并在我们自己的内核入口 `kern_entry`（即 `0x80200000`）处设置断点。再次 `continue`，程序在执行完 OpenSBI 的引导流程后，停在了我们内核的第一行汇编代码上。

通过以上步骤，我成功地观察到了从 Boot ROM -> OpenSBI -> Kernel 的完整控制权移交链条。
#### 问题回答
##### 问题1：RISC-V 硬件加电后最初执行的几条指令位于什么地址？

**回答：**
通过 GDB 调试，我观察到，在 QEMU `virt` 平台上模拟的 RISC-V 硬件“加电”后，CPU 最初执行的指令位于物理地址 `0x1000`。

##### 问题2：最初的几条指令主要完成了哪些功能？

**回答：**
位于 `0x1000`处的 Boot ROM代码有以下两个功能：
1. 建立最小化执行环境：进行最基础的硬件设置，例如可能会初始化一些关键的控制状态寄存器（CSRs），为跳转到更复杂的软件环境做准备。
2. 移交控制权：其最终、也是最重要的任务，是执行一条跳转指令，将 CPU 的控制权永久地移交给下一阶段的引导加载程序（Bootloader）。在本次实验中，它跳转到了位于物理地址 `0x80000000` 的 OpenSBI 固件。
### 学习收获

1. **系统启动理解**：

深入理解了计算机系统从硬件启动到操作系统内核加载的完整流程。认识到引导加载程序和操作系统内核的分工协作关系，前者负责早期硬件初始化，后者负责系统功能实现。

2. **RISC-V 架构认知**：

掌握了 RISC-V 汇编语言的基本语法，理解了其特权模式和 SBI 接口机制。RISC-V 架构设计简洁清晰，相比 x86 架构更易于学习和理解。

3. **交叉编译技能**：

熟练掌握了交叉编译工具链的使用方法，这对嵌入式开发具有重要意义。理解了链接脚本的作用，认识到程序内存布局设计的重要性。

4. **断点调试技术**：
   - 学习了如何通过断点调试了解整个程序的运行过程


### 技术难点分析

1. **内存布局设计**：

   - 需要精确控制内核各段的地址分布
   - 栈和 BSS 段的对齐要求需要仔细处理

2. **断点设置**：

   - 需要设置合适的断点位置，得到程序运行的流程。

### 改进建议

1. **代码结构优化**：

   - 采用模块化设计，将启动代码和初始化代码分离
   - 增加错误处理和调试信息输出机制

2. **文档完善**：

   - 为关键函数添加详细的注释说明
   - 建立完整的内存映射文档

3. **测试增强**：
   - 添加启动过程中各阶段的检查点
   - 实现更完善的内核自检机制

## 实验总结

本次实验成功完成了内核启动基础的学习任务。通过实践掌握了：

- 完整的操作系统内核编译和启动流程
- RISC-V 架构的基本概念和汇编编程
- 交叉编译工具链的使用方法
- 内核调试和分析技术

实验过程中深刻体会到操作系统底层实现的复杂性和精确性，为后续的内存管理和中断处理实验奠定了坚实的基础。
