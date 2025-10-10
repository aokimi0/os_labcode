# UCore 操作系统实验项目

这是一个基于 RISC-V 架构的操作系统内核实验项目，旨在帮助学生理解操作系统核心概念和实现机制。

## 项目简介

本项目包含三个实验（Lab1-Lab3），涵盖了操作系统的基础组件：

- **Lab1**: 内核启动和基本环境搭建
- **Lab2**: 物理内存管理（包括多种分配算法）
- **Lab3**: 中断处理、时钟管理和系统调用

项目使用 RISC-V 64 位架构，采用 C 语言和汇编语言混合编程，通过 QEMU 模拟器运行。

## 实验资源

- **实验指导书**: http://oslab.mobisys.cc/lab2025/_book/index.html
- **实验资源汇总**: http://oslab.mobisys.cc/

## 实验内容

### Lab1: 内核启动基础

- 搭建 RISC-V 交叉编译环境
- 配置 QEMU 模拟器和 OpenSBI 固件
- 实现基本的内核启动流程
- 输出内核加载信息

### Lab2: 物理内存管理

- **练习 1**: 理解 First-Fit 连续物理内存分配算法
- **练习 2**: 实现 Best-Fit 页面分配算法
- **扩展练习**: 伙伴系统（Buddy System）分配算法
- **扩展练习**: SLUB 内存分配算法

### Lab3: 中断和系统管理

- 中断描述符表的初始化和配置
- 异常处理的实现
- 时钟中断和定时器管理
- 内核调试和监控功能

## 环境要求

### 硬件要求

- x86_64 架构的现代处理器
- 至少 2GB 可用内存
- 支持硬件虚拟化的 CPU（推荐）

### 软件依赖

- Ubuntu 20.04.5 LTS 或兼容 Linux 发行版
- RISC-V 交叉编译工具链（riscv64-unknown-elf-gcc）
- QEMU 系统仿真器（riscv64 架构支持）
- 标准开发工具（make、gcc 等）

## 环境搭建指南

### 1. 安装 RISC-V 工具链

从 SiFive 官网下载预编译工具链：

```bash
wget https://static.dev.sifive.com/dev-tools/freedom-tools/v2020.12/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-linux-ubuntu14.tar.gz
sudo tar -xzf riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-linux-ubuntu14.tar.gz -C /opt
echo 'export RISCV=/opt/riscv' >> ~/.bashrc
echo 'export PATH=$RISCV/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

验证安装：

```bash
riscv64-unknown-elf-gcc -v
```

### 2. 安装 QEMU

```bash
sudo apt update
sudo apt install qemu-system-riscv64
sudo apt install libglib2.0-dev libpixman-1-dev  # 解决依赖问题
```

验证安装：

```bash
qemu-system-riscv64 --version
```

### 3. 验证环境完整性

```bash
qemu-system-riscv64 -machine virt -nographic -bios default
```

### 4. IDE (Cursor/VS Code) 配置指南

为了在现代代码编辑器中获得最佳体验（如代码补全、跳转和实时错误检查），推荐使用 `clangd` 插件。以下步骤将指导你如何正确配置 `clangd` 以识别本项目的交叉编译环境。

#### 4.1 安装 `make` 和 `bear`

`make` 是项目构建工具，而 `bear` 是一个可以生成 `clangd` 配置文件 (`compile_commands.json`) 的工具。

```bash
# 安装 make, gcc 等核心构建工具
sudo apt install -y build-essential

# 安装 bear
sudo apt install -y bear
```

#### 4.2 生成 clangd 配置文件

你需要为每个实验（lab）单独生成配置文件。这样可以确保 `clangd` 使用完全正确的编译指令来分析代码。

**以 `lab1` 为例:**

```bash
cd lab1
bear -- make
```

该命令执行后，会在 `lab1` 目录下生成一个 `compile_commands.json` 文件。对 `lab2`, `lab3` 等其他实验，重复此步骤即可。

#### 4.3 重启 clangd

在生成配置文件后，回到 Cursor 或 VS Code，打开命令面板 (Ctrl+Shift+P)，然后运行 `clangd: Restart language server` 命令。

完成以上步骤后，IDE 中的 `file not found` 等错误应该会全部消失。

## 构建和运行

### 编译项目

进入对应实验目录：

```bash
cd lab1
make
```

### 运行内核

```bash
make qemu
```

### 调试模式

```bash
make debug
```

然后在另一个终端运行：

```bash
make gdb
```

## 项目结构

```
os_labcode/
├── lab1/                    # 实验一：内核启动
│   ├── kern/               # 内核代码
│   │   ├── init/          # 初始化代码
│   │   ├── driver/        # 设备驱动
│   │   ├── libs/          # 基础库函数
│   │   └── mm/            # 内存管理
│   ├── libs/              # 公共库
│   ├── tools/             # 构建工具和脚本
│   ├── bin/               # 生成的可执行文件
│   ├── obj/               # 编译中间文件
│   └── report/            # 实验报告
├── lab2/                  # 实验二：物理内存管理
│   ├── kern/mm/           # 内存管理实现
│   │   ├── default_pmm.c  # First-Fit算法
│   │   ├── best_fit_pmm.c # Best-Fit算法
│   │   └── pmm.c          # 内存管理框架
│   └── libs/              # 数据结构和工具库
└── lab3/                  # 实验三：中断处理
    ├── kern/trap/         # 中断处理
    ├── kern/debug/        # 调试功能
    ├── kern/driver/       # 设备驱动（含时钟）
    └── kern/sync/         # 同步机制
```

## 关键文件说明

### 核心启动文件

- `kern/init/entry.S`: 内核入口点汇编代码
- `kern/init/init.c`: 内核初始化主函数

### 内存管理

- `kern/mm/pmm.c`: 物理内存管理框架
- `kern/mm/default_pmm.c`: First-Fit 分配算法
- `kern/mm/best_fit_pmm.c`: Best-Fit 分配算法
- `kern/mm/memlayout.h`: 内存布局定义

### 中断处理

- `kern/trap/trap.c`: 中断处理主函数
- `kern/trap/trapentry.S`: 中断入口汇编代码
- `kern/trap/vectors.S`: 中断向量表

### 设备驱动

- `kern/driver/console.c`: 控制台驱动
- `kern/driver/clock.c`: 时钟驱动
- `kern/driver/intr.c`: 中断控制器驱动

## 实验成果

本项目成功实现了：

1. ✅ 完整的 RISC-V 内核启动流程
2. ✅ 多种物理内存分配算法（First-Fit、Best-Fit）
3. ✅ 中断处理和异常管理机制
4. ✅ 时钟管理和定时器功能
5. ✅ 内核调试和监控工具

## 技术特点

- **架构**: 基于 RISC-V 64 位架构（RV64）
- **编程语言**: C 语言 + RISC-V 汇编
- **内存管理**: 支持多种分配策略，可扩展性强
- **中断处理**: 完整的异常处理框架
- **调试支持**: 集成 GDB 调试功能
- **模块化设计**: 清晰的层次结构，易于理解和维护
