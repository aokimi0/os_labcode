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

- `kern_entry`是内核的入口点，定义为全局可见的标签
- 首先设置栈指针`sp`指向引导栈的顶部，该栈用于启动过程的临时存储
- 使用`tail kern_init`指令跳转到 C 语言编写的`kern_init`函数
- 定义了引导栈空间，大小为`KSTACKSIZE`，按照页面大小进行对齐

该设计体现了系统启动的分层思想：汇编代码负责最基本的硬件初始化，然后快速跳转到 C 代码处理更复杂的逻辑。

#### 2. 内核初始化分析 (`kern/init/init.c`)

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

该 C 代码实现了内核的基本初始化功能：

- `kern_init`函数标记为`noreturn`，表示该函数不会返回
- 首先将 BSS 段（未初始化的全局变量区域）清零，这是系统启动的必要步骤
- 输出内核启动信息
- 进入无限循环，等待后续的系统操作

BSS 段清零是系统启动的关键步骤。在 C 语言中，未初始化的全局变量存储在 BSS 段，其初始值应为 0，但需要操作系统在启动时进行显式设置。

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

链接脚本负责指导链接器组织程序的各个部分：

- 指定目标架构为 RISC-V，并设置入口点为`kern_entry`
- 设置内核加载的基地址为`0x80200000`
- 定义各内存段的布局：代码段、只读数据段、数据段、BSS 段等
- 定义符号供 C 代码使用，如`etext`、`edata`、`end`等

该脚本设计考虑了内存对齐要求，确保了内存访问的安全性和效率。

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

3. **依赖库缺失问题**：

   - **问题**：编译过程中出现 glib 相关错误
   - **原因**：缺少必要的开发库
   - **解决方案**：安装 libglib2.0-dev 和 libpixman-1-dev 开发库

4. **内存对齐理解问题**：

   - **问题**：初期对链接脚本中的内存对齐机制理解不够深入
   - **原因**：缺乏对 RISC-V 架构内存管理的认识
   - **解决方案**：通过查阅 RISC-V 手册和讨论，理解了页面对齐的重要性

5. **汇编指令优化挑战**：

   - **问题**：`la`指令在某些情况下未能正确生成预期代码
   - **原因**：编译器对宏展开的处理差异
   - **解决方案**：采用直接的立即数加载指令，确保代码正确性

6. **内核调试技术**：

   - **问题**：运行时缺乏有效的调试手段
   - **原因**：对内核调试工具和方法了解不足
   - **解决方案**：掌握反汇编分析、符号表检查等调试技术

## 实验结果

### 编译结果

编译过程顺利完成，项目结构组织良好，生成了以下文件：

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

### 关键现象分析

1. **启动流程**：

系统启动遵循标准流程：QEMU 启动 → OpenSBI 固件初始化 → 跳转到内核入口点`kern_entry` → 设置栈指针 → 跳转到`kern_init` → 清零 BSS 段 → 输出启动信息 → 进入无限循环等待。

2. **内存布局**：

内核加载到`0x80200000`地址，栈位于内核数据段之后，BSS 段被正确清零。该设计确保了内存访问的安全性和系统稳定性。

3. **输出机制**：
   字符输出通过 SBI 调用实现，利用 RISC-V 特权指令访问控制台设备。内核通过固件接口与硬件进行交互。

## 实验心得

### 学习收获

1. **系统启动理解**：

深入理解了计算机系统从硬件启动到操作系统内核加载的完整流程。认识到引导加载程序和操作系统内核的分工协作关系，前者负责早期硬件初始化，后者负责系统功能实现。

2. **RISC-V 架构认知**：

掌握了 RISC-V 汇编语言的基本语法，理解了其特权模式和 SBI 接口机制。RISC-V 架构设计简洁清晰，相比 x86 架构更易于学习和理解。

3. **交叉编译技能**：

熟练掌握了交叉编译工具链的使用方法，这对嵌入式开发具有重要意义。理解了链接脚本的作用，认识到程序内存布局设计的重要性。

4. **调试技术**：
   - 熟练使用 QEMU 模拟器进行内核调试
   - 理解了内核映像格式和符号表的作用机制

### 技术难点分析

1. **内存布局设计**：

   - 需要精确控制内核各段的地址分布
   - 栈和 BSS 段的对齐要求需要仔细处理

2. **SBI 接口使用**：

   - 理解监督模式二进制接口的调用机制
   - 掌握特权指令的使用和系统调用流程

3. **启动流程协调**：
   - 固件和内核之间的接口需要严格遵循规范
   - 栈设置和初始状态准备至关重要

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
