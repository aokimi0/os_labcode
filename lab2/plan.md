# Lab2 物理内存管理与挑战实现计划

## 目标

- 完成 First-Fit（阅读与对照）、Best-Fit（实现并设为默认）、Buddy System（新增）、SLUB（新增）。
- 确保 `make grade` 通过（使用 Best-Fit）。
- 提供 Buddy/SLUB 的独立测试与简要文档答题，更新 `lab2/lab2.md`。

## 关键改动点

- 切换默认内存管理器为 Best-Fit：修改 `kern/mm/pmm.c` 的 `init_pmm_manager`。

```35:40:lab2/kern/mm/pmm.c
static void init_pmm_manager(void) {
    pmm_manager = &default_pmm_manager;
    cprintf("memory management: %s\n", pmm_manager->name);
    pmm_manager->init();
}
```

- 完成 `best_fit_pmm.c` 中的 TODO：
  - `best_fit_init_memmap`：清标志/属性、ref=0、按地址有序插入空闲链表。
  - `best_fit_alloc_pages`：遍历求“最小能装下 n 的块”（best-fit），切割尾部、维护 `nr_free` 与标志。
  - `best_fit_free_pages`：设置属性、插入、与前后相邻块合并、维护 `nr_free`。
- 新增 Buddy System：`kern/mm/buddy_pmm.{h,c}`，实现 `struct pmm_manager` 同名接口、带 `buddy_check()` 自测。
- 新增 SLUB：`kern/mm/slub.{h,c}`，实现 `slub_init/ kmalloc/ kfree`，页级分配来自 `alloc_pages/free_pages`，提供 `slub_check()` 自测。
- 保持默认 Manager 为 Best-Fit 以满足 `tools/grade.sh` 的输出校验；Buddy/SLUB 通过独立测试目标运行，不影响默认 `grade`。

## 新增/修改文件

- 修改：`lab2/kern/mm/pmm.c`（默认改为 Best-Fit）。
- 修改：`lab2/kern/mm/best_fit_pmm.c`（补全 TODO）。
- 新增：`lab2/kern/mm/buddy_pmm.h`, `lab2/kern/mm/buddy_pmm.c`。
- 新增：`lab2/kern/mm/slub.h`, `lab2/kern/mm/slub.c`。
- 新增：`lab2/tests/buddy_test.c`, `lab2/tests/slub_test.c`（内核内断言样式，受宏控制）。
- 修改：`lab2/Makefile`（添加 `grade-buddy`, `grade-slub` 目标与宏开关，不改默认 `grade` 流程）。
- 修改：`lab2/tools/grade.sh`（可选：添加 `grade_buddy.sh`, `grade_slub.sh` 独立脚本，不影响原脚本）。
- 修改：`lab2/lab2.md`（填写思考题与实现说明）。

## 实现要点

- First-Fit：保持现有 `default_pmm.c`（已实现），只在文档中对照分析。
- Best-Fit：
  - 维护按地址有序的空闲块链表；分配时线性遍历挑选最小可用块。
  - 切割策略：保留头指针不动，分裂出尾部残余块并重新挂链。
  - 释放合并：尝试与前/后相邻物理块合并，维护头页 `property` 与标志。
  - 文档中的优化建议：可选用“线段树/平衡树+桶”加速查找最小可用块（O(log N)），或分离适配（按区间大小分桶），与本实验评分无关，仅作改进讨论。
- Buddy System：
  - 维护每阶（order 0..MAX_ORDER）空闲链表；`init_memmap` 将页对齐聚合入对应阶桶。
  - 分配时从 >=need_order 的最小阶取块并逐阶拆分；释放时逐阶向上合并伙伴块。
  - 页头使用 `property` 存 order，空闲头页标 `PG_property`，链表为同阶桶。
- SLUB：
  - 预设一组 size-class（如 16/32/64/128/256/512/1024/2048/4096）；小于等于 4096 的对象从对应 slab 获取；>4096 直接整页分配。
  - 每个 kmem_cache 维护部分/满/空三类链表；空 slab 由 `alloc_pages(1)` 获取，释放回收后若空则 `free_pages`。

## 测试与打分

- `make grade`：保持脚本不变，输出中包含：
  - `memory management: best_fit_pmm_manager`
  - `check_alloc_page() succeeded!` 与期望的 satp 地址打印。
- 新增：
  - `make grade-buddy`：运行 `buddy_check()` 并校验输出/断言。
  - `make grade-slub`：运行 `slub_check()` 并校验输出/断言。

## 文档

- 在 `lab2/lab2.md` 填写：
  - 练习 1：First-Fit 流程、函数职责、可改进点。
  - 练习 2：Best-Fit 设计与释放合并、改进点（如分离适配 + 地址有序 + 次序桶）。
  - 挑战：Buddy 设计、复杂度、内外碎片分析、测试说明；SLUB 设计、size-class、对象/页生命周期、测试说明。
  - 思考题：未知物理内存范围的获取（DTB/BIOS/E820/SBI/固件接口）。
