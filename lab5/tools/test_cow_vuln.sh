#!/bin/bash
# Lab5 Challenge1: Dirty COW 漏洞演示脚本
# 增强版：添加重试机制、更好的错误处理、更长超时

set -o pipefail

cd "$(dirname "$0")/.."

# 配置参数
TIMEOUT=15          # QEMU 超时时间（秒）
MAX_RETRIES=2       # 最大重试次数
LOG_FILE=".cowdirty_vuln.log"

echo "======================================================================"
echo "Lab5 Challenge1: Dirty COW 风格漏洞演示"
echo "======================================================================"
echo ""

# 清理旧日志
rm -f "$LOG_FILE"

# 清理旧构建
echo "[1/4] 清理旧构建..."
make clean >/dev/null 2>&1

# 编译漏洞演示版本
echo "[2/4] 编译漏洞演示版本（ENABLE_COW + COW_DIRTY_VULN）..."
if ! make build-cowdirty DEFS="-DENABLE_COW -DCOW_DIRTY_VULN" 2>&1 | tee .build.log | grep -E '^(\+|make)' | tail -5; then
    echo "  编译输出已保存到 .build.log"
fi

# 检查编译产物
echo "[3/4] 检查编译产物..."
if [[ ! -f "bin/ucore.img" ]]; then
    echo "✗ 编译失败：bin/ucore.img 不存在"
    echo "  完整编译日志："
    cat .build.log 2>/dev/null | tail -20
    exit 1
fi
echo "  bin/ucore.img 已生成 ($(stat -c%s bin/ucore.img 2>/dev/null || stat -f%z bin/ucore.img 2>/dev/null) bytes)"

# 运行测试（带重试）
echo "[4/4] 运行 cowdirty（最多重试 $MAX_RETRIES 次）..."
echo ""

run_test() {
    # 使用文件直接写入，避免管道缓冲问题
    # 注意：重定向顺序必须是 > file 2>&1，而不是 2>&1 > file
    timeout "$TIMEOUT" qemu-system-riscv64 \
        -machine virt \
        -nographic \
        -bios default \
        -device loader,file=bin/ucore.img,addr=0x80200000 \
        -serial stdio \
        -monitor null \
        -no-reboot > "$LOG_FILE" 2>&1
    
    local exit_code=$?
    
    # 显示关键输出
    grep -E '(kernel_execve.*cowdirty|dirtycow|check memory|panic|assert)' "$LOG_FILE" 2>/dev/null
    
    return $exit_code
}

success=false
for ((i=1; i<=MAX_RETRIES; i++)); do
    echo "--- 尝试 $i/$MAX_RETRIES ---"
    
    run_test
    qemu_exit=$?
    
    # 检查结果
    if grep -q 'dirtycow vulnerable (demo)' "$LOG_FILE" 2>/dev/null; then
        success=true
        break
    fi
    
    # 如果 QEMU 超时，提示
    if [[ $qemu_exit -eq 124 ]]; then
        echo "  (QEMU 超时，可能需要更长时间)"
    fi
    
    if [[ $i -lt $MAX_RETRIES ]]; then
        echo "  重试中..."
        sleep 1
    fi
done

echo ""
echo "======================================================================"
if $success; then
    echo "✓ Dirty COW 漏洞演示成功！"
    echo ""
    echo "漏洞原理（CVE-2016-5195 风格）："
    echo "  1. fork 时父进程页表本应降权为只读，但 TLB 未刷新"
    echo "  2. 父进程使用陈旧的 TLB 条目，仍有可写权限"
    echo "  3. 父进程写入直接穿透到共享物理页"
    echo "  4. 子进程看到了父进程的修改 → 隔离被破坏"
    echo ""
    echo "修复方案："
    echo "  • fork 后必须对父进程执行 TLB 刷新（sfence.vma）"
    echo "  • 确保页表权限变更立即生效"
    exit 0
else
    echo "✗ Dirty COW 漏洞演示失败"
    echo ""
    echo "完整日志（最后 30 行）："
    echo "----------------------------------------------------------------------"
    tail -30 "$LOG_FILE" 2>/dev/null || echo "(日志为空)"
    echo "----------------------------------------------------------------------"
    echo ""
    echo "检查项："
    echo "  1. 是否正确编译了 COW_DIRTY_VULN 宏？"
    echo "  2. vmm.c 中是否实现了条件跳过 TLB 刷新？"
    echo "  3. 检查 grep 'COW_DIRTY_VULN' kern/mm/vmm.c"
    exit 1
fi
