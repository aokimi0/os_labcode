#!/bin/sh

#
# @file
# @brief Lab3 自动化验证脚本（RISC-V, QEMU）。
#
# - 构建内核镜像并以 QEMU 启动；
# - 捕获串口输出到 `GRADE_QEMU_OUT`；
# - 校验关键输出行，按权重计分；
# - 支持 -v 打印调试信息。
#
# 约定：Makefile 提供以下打印目标：print-GDB/print-QEMU/print-GRADE_GDB_IN/print-GRADE_QEMU_OUT/print-ucoreimg/print-swapimg。
#

verbose=false
if [ "x$1" = "x-v" ]; then
    verbose=true
else
    out=/dev/null
    err=/dev/null
fi

## 选择 make 实现
if gmake --version > /dev/null 2>&1; then
    make=gmake
else
    make=make
fi

makeopts="--quiet --no-print-directory -j"

make_print() {
    echo `$make $makeopts print-$1`
}

## 工具
awk='awk'
bc='bc'
date='date'
grep='grep'
rm='rm -f'
sed='sed'

## 符号表（若需要断点）
sym_table='obj/kernel.sym'

## GDB 与脚本输入
gdb="$(make_print GDB)"
gdbport='1234'
gdb_in="$(make_print GRADE_GDB_IN)"

## QEMU 与输出文件
qemu="$(make_print QEMU)"
qemu_out="$(make_print GRADE_QEMU_OUT)"

## gdb 形式
if $qemu -nographic -help | grep -q '^-gdb'; then
    qemugdb="-gdb tcp::$gdbport"
else
    qemugdb="-s -p $gdbport"
fi

## 默认参数
default_timeout=30
default_pts=5
grade_debug=1

pts=5
part=0
part_pos=0
total=0
total_pos=0

## 通用方法
update_score() {
    total=`expr $total + $part`
    total_pos=`expr $total_pos + $part_pos`
    part=0
    part_pos=0
}

get_time() {
    echo `$date +%s.%N 2> /dev/null`
}

show_part() {
    echo "Part $1 Score: $part/$part_pos"
    echo
    update_score
}

show_final() {
    update_score
    echo "Total Score: $total/$total_pos"
    if [ $total -lt $total_pos ]; then
        exit 1
    fi
}

show_time() {
    t1=$(get_time)
    time=`echo "scale=1; ($t1-$t0)/1" | $sed 's/.N/.0/g' | $bc 2> /dev/null`
    echo "(${time}s)"
}

show_build_tag() {
    echo "$1:" | $awk '{printf "%-24s ", $0}'
}

show_check_tag() {
    echo "$1:" | $awk '{printf "  -%-40s  ", $0}'
}

show_msg() {
    echo $1
    shift
    if [ $# -gt 0 ]; then
        echo -e "$@" | awk '{printf "   %s\n", $0}'
        echo
    fi
}

pass() {
    show_msg OK "$@"
    part=`expr $part + $pts`
    part_pos=`expr $part_pos + $pts`
}

fail() {
    show_msg WRONG "$@"
    part_pos=`expr $part_pos + $pts`
}

## QEMU 运行
qemuopts="-machine virt -nographic -bios default -device loader,file=bin/ucore.img,addr=0x80200000"

run_qemu() {
    # 可选断点等待：若设置 brkfun，则用 gdb 连续再杀掉 QEMU
    qemuextra=
    if [ "$brkfun" ]; then
        qemuextra="-S $qemugdb"
    fi

    if [ -z "$timeout" ] || [ $timeout -le 0 ]; then
        timeout=$default_timeout
    fi

    t0=$(get_time)
    if $verbose; then
        (
            ulimit -t $timeout
            exec $qemu -nographic $qemuopts -serial file:$qemu_out -monitor null -no-reboot $qemuextra
        ) &
    else
        (
            ulimit -t $timeout
            exec $qemu -nographic $qemuopts -serial file:$qemu_out -monitor null -no-reboot $qemuextra
        ) > $out 2> $err &
    fi
    pid=$!

    # 启动等待
    sleep 1

    if [ -n "$brkfun" ]; then
        brkaddr=`$grep " $brkfun$" $sym_table | $sed -e's/ .*$//g'`
        brkaddr_phys=`echo $brkaddr | sed "s/^c0/00/g"`
        (
            echo "target remote localhost:$gdbport"
            echo "break *0x$brkaddr"
            if [ "$brkaddr" != "$brkaddr_phys" ]; then
                echo "break *0x$brkaddr_phys"
            fi
            echo "continue"
        ) > $gdb_in
        $gdb -batch -nx -x $gdb_in > /dev/null 2>&1
        kill $pid > /dev/null 2>&1
    fi
}

build_run() {
    # usage: build_run <tag> <make_defs>
    tag="$1"
    shift
    show_build_tag "$tag"

    if $verbose; then
        echo "$make $@ ..."
        if [ "x$grade_debug" = "x1" ]; then
            $make $makeopts $@ 'DEFS+=-DDEBUG_GRADE'
        else
            $make $makeopts $@
        fi
    else
        if [ "x$grade_debug" = "x1" ]; then
            $make $makeopts $@ 'DEFS+=-DDEBUG_GRADE' > $out 2> $err
        else
            $make $makeopts $@ > $out 2> $err
        fi
    fi
    if [ $? -ne 0 ]; then
        echo $make $@ failed
        exit 1
    fi

    # 运行 QEMU
    $make $makeopts touch > /dev/null 2>&1
    run_qemu

    show_time
    # 保存日志
    cp $qemu_out .`echo $tag | tr '[:upper:]' '[:lower:]' | sed 's/ /_/g'`.log
}

check_result() {
    # usage: check_result <tag> <check> <check args...>
    show_check_tag "$1"
    shift

    # 等待串口输出
    if [ ! -s $qemu_out ]; then
        sleep 4
    fi

    if [ ! -s $qemu_out ]; then
        fail > /dev/null
        echo 'no $qemu_out'
    else
        check=$1
        shift
        $check "$@"
    fi

    # 清理 QEMU
    if [ -n "$pid" ]; then
        kill $pid > /dev/null 2>&1
    fi
}

check_regexps() {
    okay=yes
    not=0
    reg=0
    error=
    for i do
        if [ "x$i" = "x!" ]; then
            not=1
        elif [ "x$i" = "x-" ]; then
            reg=1
        else
            if [ $reg -ne 0 ]; then
                $grep '-E' "^$i$" $qemu_out > /dev/null
            else
                $grep '-F' "$i" $qemu_out > /dev/null
            fi
            found=$(($? == 0))
            if [ $found -eq $not ]; then
                if [ $found -eq 0 ]; then
                    msg="!! error: missing '$i'"
                else
                    msg="!! error: got unexpected line '$i'"
                fi
                okay=no
                if [ -z "$error" ]; then
                    error="$msg"
                else
                    error="$error\n$msg"
                fi
            fi
            not=0
            reg=0
        fi
    done
    if [ "$okay" = "yes" ]; then
        pass
    else
        fail "$error"
        if $verbose; then
            exit 1
        fi
    fi
}

run_test() {
    # usage: run_test [-tag <tag>] [-Ddef...] [-check <check>] checkargs ...
    tag=
    check=check_regexps
    while true; do
        select=
        case $1 in
            -tag)
                select=`expr substr $1 2 ${#1}`
                eval $select='$2'
                ;;
        esac
        if [ -z "$select" ]; then
            break
        fi
        shift
        shift
    done
    defs=
    while expr "x$1" : "x-D.*" > /dev/null; do
        defs="DEFS+='$1' $defs"
        shift
    done
    if [ "x$1" = "x-check" ]; then
        check=$2
        shift
        shift
    fi

    $make $makeopts touch > /dev/null 2>&1
    build_run "$tag" "$defs"
    check_result 'check result' "$check" "$@"
}

quick_run() {
    # usage: quick_run <tag> [-Ddef...]
    tag="$1"
    shift
    defs=
    while expr "x$1" : "x-D.*" > /dev/null; do
        defs="DEFS+='$1' $defs"
        shift
    done
    $make $makeopts touch > /dev/null 2>&1
    build_run "$tag" "$defs"
}

quick_check() {
    # usage: quick_check <tag> checkargs ...
    tag="$1"
    shift
    check_result "$tag" check_regexps "$@"
}

# 将 .qemu.out 关键行同步打印到控制台
start_ticks_stream() {
    # 仅打印关键信息，避免噪声
    (
        tail -n +1 -f "$qemu_out" 2>/dev/null | grep -E '^(\+\+ setup timer interrupts|100 ticks|End of Test\.)$'
    ) &
    stream_pid=$!
}

stop_ticks_stream() {
    if [ -n "$stream_pid" ]; then
        kill $stream_pid > /dev/null 2>&1 || true
        stream_pid=
    fi
}

# 检查 100 ticks 是否约 1s 一次、累计 10 次后自动关机
check_ticks_seconds() {
    # 启动控制台镜像输出
    start_ticks_stream
    # 等待 setup 行
    t_setup_wait=5
    while [ $t_setup_wait -gt 0 ]; do
        $grep -F '++ setup timer interrupts' $qemu_out > /dev/null && break
        sleep 0.1
        t_setup_wait=`expr $t_setup_wait - 1`
    done

    count=0
    start=
    last=
    waited=0
    # 最长等待 20s
    while [ $waited -lt 200 ]; do
        c=`$grep -c '100 ticks' $qemu_out 2>/dev/null || true`
        [ -z "$c" ] && c=0
        if [ "$c" -gt "$count" ]; then
            now=$(get_time)
            if [ -z "$start" ]; then start=$now; fi
            count=$c
            if [ "$count" -ge 10 ]; then last=$now; break; fi
        fi
        sleep 0.1
        waited=`expr $waited + 1`
    done

    if [ "$count" -lt 10 ]; then
        fail "!! error: missing 10 times '100 ticks'"
        return
    fi
    avg=`echo "scale=2; ($last-$start)/9" | $sed 's/.N/.0/g' | $bc 2>/dev/null`
    ge=`echo "$avg >= 0.6" | $bc`
    le=`echo "$avg <= 1.4" | $bc`
    if [ "$ge" = "1" ] && [ "$le" = "1" ]; then
        pass
    else
        fail "!! error: avg interval ${avg}s not around 1s"
    fi
    # 停止镜像输出
    stop_ticks_stream
    # 在控制台回显关键日志，满足人工观测需求
    echo "--- ticks console ---"
    $grep -E '^\+\+ setup timer interrupts$|^100 ticks$|^End of Test\.$' "$qemu_out" | head -n 25
    echo "---------------------"
}

## 镜像与默认选项
osimg=$(make_print ucoreimg)
swapimg=$(make_print swapimg)

## 断点函数（默认空，不进 gdb）
brkfun=

## ============= 评分用例 =============

# 物理内存信息 + default 管理器识别
pts=5
quick_run 'Check PMM'
quick_check 'check physical_memory_map_information' \
    'memory management: default_pmm_manager' \
    '  memory: 0x0000000008000000, [0x0000000080000000, 0x0000000087ffffff].'

# 分配校验（默认管理器）
pts=20
quick_run 'Check default_pmm'
quick_check 'check_default_pmm' \
    'check_alloc_page() succeeded!' \
    'satp virtual address: 0x' \
    'satp physical address: 0x'

# 时钟中断：每 ~1s 打印一次 100 ticks，并累计 10 次后自动关机
pts=5
grade_debug=0
quick_run 'Check ticks'
check_result 'check ticks timing' check_ticks_seconds
grade_debug=1

## 打印最终得分
show_final


