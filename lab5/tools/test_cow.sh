#!/bin/bash
# Lab5 Challenge1: COW 功能测试脚本
# 增强版：添加重试机制、更好的错误处理、更长超时

set -o pipefail

cd "$(dirname "$0")/.."

# 配置参数
TIMEOUT=15          # QEMU 超时时间（秒）
MAX_RETRIES=2       # 最大重试次数
LOG_FILE=".cowtest.log"

echo "======================================================================"
echo "Lab5 Challenge1: Copy-on-Write (COW) 功能测试"
echo "======================================================================"
echo ""

# 清理旧日志
rm -f "$LOG_FILE"

# 清理旧构建
echo "[1/4] 清理旧构建..."
make clean >/dev/null 2>&1

# 编译 COW 版本
echo "[2/4] 编译 COW 版本（ENABLE_COW）..."
if ! make build-cowtest DEFS=-DENABLE_COW 2>&1 | tee .build.log | grep -E '^(\+|make)' | tail -5; then
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
echo "[4/4] 运行 cowtest（最多重试 $MAX_RETRIES 次）..."
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
    grep -E '(kernel_execve.*cowtest|cowtest pass|check memory|panic|assert)' "$LOG_FILE" 2>/dev/null
    
    return $exit_code
}

success=false
for ((i=1; i<=MAX_RETRIES; i++)); do
    echo "--- 尝试 $i/$MAX_RETRIES ---"
    
    run_test
    qemu_exit=$?
    
    # 检查结果
    if grep -q 'cowtest pass' "$LOG_FILE" 2>/dev/null; then
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
    echo "✓ COW 功能测试通过！"
    echo ""
    echo "验证内容："
    echo "  • fork 后父子共享物理页（只读+COW 标记）"
    echo "  • 子进程写入触发 COW 拷贝"
    echo "  • 父子修改互不可见（隔离验证）"
    exit 0
else
    echo "✗ COW 功能测试失败"
    echo ""
    echo "完整日志（最后 30 行）："
    echo "----------------------------------------------------------------------"
    tail -30 "$LOG_FILE" 2>/dev/null || echo "(日志为空)"
    echo "----------------------------------------------------------------------"
    echo ""
    echo "可能原因："
    echo "  1. COW page fault 处理未正确实现"
    echo "  2. 页表权限设置错误"
    echo "  3. 进程调度或同步问题"
    exit 1
fi
