#!/bin/sh

verbose=false
if [ "x$1" = "x-v" ]; then
    verbose=true
    out=/dev/stdout
    err=/dev/stderr
else
    out=/dev/null
    err=/dev/null
fi

if gmake --version > /dev/null 2>&1; then make=gmake; else make=make; fi
makeopts="--quiet --no-print-directory -j"

awk='awk'; bc='bc'; date='date'; grep='grep'; rm='rm -f'; sed='sed'
sym_table='obj/kernel.sym'
gdb='riscv64-unknown-elf-gdb'; gdbport='1234'
gdb_in='.gdb.in'
qemu='qemu-system-riscv64'
qemu_out='.qemu.out'

if $qemu -nographic -help | grep -q '^-gdb'; then qemugdb="-gdb tcp::$gdbport"; else qemugdb="-s -p $gdbport"; fi
default_timeout=30; pts=5; part=0; part_pos=0; total=0; total_pos=0

update_score(){ total=`expr $total + $part`; total_pos=`expr $total_pos + $part_pos`; part=0; part_pos=0; }
show_build_tag(){ echo "$1:" | $awk '{printf "%-24s ", $0}'; }
show_check_tag(){ echo "$1:" | $awk '{printf "  -%-40s  ", $0}'; }
show_msg(){ echo $1; shift; if [ $# -gt 0 ]; then echo -e "$@" | awk '{printf "   %s\n", $0}'; echo; fi }
pass(){ show_msg OK "$@"; part=`expr $part + $pts`; part_pos=`expr $part_pos + $pts`; }
fail(){ show_msg WRONG "$@"; part_pos=`expr $part_pos + $pts`; }

run_qemu(){
    qemuextra=
    if [ -n "$brkfun" ]; then qemuextra="-S $qemugdb"; fi
    if [ -z "$timeout" ] || [ $timeout -le 0 ]; then timeout=$default_timeout; fi
    (
        ulimit -t $timeout
        exec $qemu -nographic $qemuopts -serial file:$qemu_out -monitor null -no-reboot $qemuextra
    ) > $out 2> $err &
    pid=$!
    sleep 1
}

build_run(){
    show_build_tag "$1"; shift
    $make $makeopts $@ 'DEFS+=-DDEBUG_GRADE' > $out 2> $err || { echo build failed; exit 1; }
    run_qemu
}

check_result(){ show_check_tag "$1"; shift; if [ ! -s $qemu_out ]; then fail > /dev/null; else $1 "$@"; fi }

check_regexps(){
    okay=yes; not=0; reg=0; error=
    for i do
        if [ "x$i" = "x!" ]; then not=1
        elif [ "x$i" = "x-" ]; then reg=1
        else
            if [ $reg -ne 0 ]; then $grep '-E' "^$i$" $qemu_out > /dev/null; else $grep '-F' "$i" $qemu_out > /dev/null; fi
            found=$(($? == 0))
            if [ $found -eq $not ]; then
                if [ $found -eq 0 ]; then msg="!! error: missing '$i'"; else msg="!! error: got unexpected line '$i'"; fi
                okay=no; if [ -z "$error" ]; then error="$msg"; else error="$error\n$msg"; fi
            fi
            not=0; reg=0
        fi
    done
    if [ "$okay" = "yes" ]; then pass; else fail "$error"; fi
}

run_test(){ tag=; check=check_regexps; while true; do select=; case $1 in -tag) select=`expr substr $1 2 ${#1}`; eval $select='$2';; esac; if [ -z "$select" ]; then break; fi; shift; shift; done; defs=; while expr "x$1" : "x-D.*" > /dev/null; do defs="DEFS+='$1' $defs"; shift; done; if [ "x$1" = "x-check" ]; then check=$2; shift; shift; fi; $make $makeopts touch > /dev/null 2>&1; build_run "$tag" "$defs"; check_result 'check result' "$check" "$@"; }

osimg=$(make_print ucoreimg)
qemuopts="-machine virt -nographic -bios default -device loader,file=bin/ucore.img,addr=0x80200000"
brkfun=

$make $makeopts clean > /dev/null 2>&1

pts=10
run_test -tag 'slub selftest' -DSLUB_SELF_TEST -check check_regexps \
    'slub_check() succeeded!'

update_score
echo "Total Score: $total/$total_pos"
if [ $total -lt $total_pos ]; then exit 1; fi


