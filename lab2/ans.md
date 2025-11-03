# 实验二：物理内存管理

对实验报告的要求：
 - 基于markdown格式来完成，以文本方式为主
 - 填写各个基本练习中要求完成的报告内容
 - 完成实验后，请分析ucore_lab中提供的参考答案，并请在实验报告中说明你的实现与参考答案的区别
 - 列出你认为本实验中重要的知识点，以及与对应的OS原理中的知识点，并简要说明你对二者的含义，关系，差异等方面的理解（也可能出现实验中的知识点没有对应的原理知识点）
 - 列出你认为OS原理中很重要，但在实验中没有对应上的知识点

#### 练习1：理解first-fit 连续物理内存分配算法（思考题）
first-fit 连续物理内存分配算法作为物理内存分配一个很基础的方法，需要同学们理解它的实现过程。请大家仔细阅读实验手册的教程并结合`kern/mm/default_pmm.c`中的相关代码，认真分析default_init，default_init_memmap，default_alloc_pages， default_free_pages等相关函数，并描述程序在进行物理内存分配的过程以及各个函数的作用。
请在实验报告中简要说明你的设计实现过程。请回答如下问题：
- 你的first fit算法是否有进一步的改进空间？
实现参见 `kern/mm/default_pmm.c`。核心数据结构为有序空闲链表 `free_list` 与空闲页计数 `nr_free`（见 `memlayout.h` 中 `free_area_t`）。流程：

- 初始化（`default_init`）: 初始化空闲链表头，`nr_free=0`。
- 建图（`default_init_memmap(base,n)`）: 对 `[base, base+n)` 中每页：清 `flags/property`、`ref=0`；将头页 `base->property=n`、`SetPageProperty(base)` 并按地址有序插入 `free_list`，`nr_free+=n`。
- 分配（`default_alloc_pages(n)`）: 线性遍历 `free_list` 找到第一个 `property>=n` 的块，摘链；若大于 `n`，在尾部切出剩余子块重新挂链；`nr_free-=n`，清除头页 `PG_property`，返回起始页。
- 释放（`default_free_pages(base,n)`）: 清页的保留/属性、`ref=0`；设置 `base->property=n` 并按地址插入；尝试与前后相邻空闲块合并，维护合并后头页 `property` 与链表；`nr_free+=n`。

改进空间：
- 时间复杂度：当前查找 O(空闲块数)。可用分离适配（按块大小分桶）、平衡树/跳表按块大小排序，降到 O(logN)。
- 外碎片：释放时已做相邻合并，可进一步用延迟合并、周期性重组。
- 多核并发：引入分段锁/每CPU缓存减少竞争。
#### 练习2：实现 Best-Fit 连续物理内存分配算法（需要编程）
在完成练习一后，参考kern/mm/default_pmm.c对First Fit算法的实现，编程实现Best Fit页面分配算法，算法的时空复杂度不做要求，能通过测试即可。
请在实验报告中简要说明你的设计实现过程，阐述代码是如何对物理内存进行分配和释放，并回答如下问题：
- 你的 Best-Fit 算法是否有进一步的改进空间？
实现位置 `kern/mm/best_fit_pmm.c`，默认启用（`pmm.c:init_pmm_manager`）。与 First-Fit 的差异在于分配选择：

- 分配（`best_fit_alloc_pages(n)`）：遍历所有空闲块，选择满足 `>=n` 且“最小可容纳”的块（best-fit）。随后同样从头返回 `page`，在尾部切割残余块重新入链，维护 `nr_free` 与 `PG_property`。
- 释放（`best_fit_free_pages`）：与 First-Fit 相同，按地址插入并尝试前后合并。

改进空间：
- 将空闲块按大小建立小根堆/平衡树，并保留按地址有序链表用于合并，查找最小可用块 O(logN)。
- 引入大小区间桶（segregated fit）降低全表扫描。
- 利用位图/伙伴化思想在页级按 2^k 对齐切割，减少外碎片。
- 线段树优化（页粒度）：以页为单位建立线段树，节点维护“区间最长连续空闲长度（max）、前缀/后缀空闲长度”。
  - 分配：查询“左侧第一个长度≥n 的位置”可通过树上二分实现，时间 O(logN)；更新为占用并自底向上维护，O(logN)。
  - 释放：恢复区间空闲并自底向上合并，O(logN)。
  - 优点：定位与合并均为对数复杂度，适合快速 First-Fit；缺点：内存开销≈4N 节点，且难以精确“最佳适配”（best-fit），可结合“按大小桶/平衡树记录候选块”实现近似 best-fit（先用线段树判定存在并定位，再在近邻大小桶中挑最小可用）。
#### 扩展练习Challenge：buddy system（伙伴系统）分配算法（需要编程）
实现位置 `kern/mm/buddy_pmm.{h,c}`，通过 `-DPMM_MANAGER_BUDDY` 启用。设计要点：
- 桶：`order 0..16`，阶 k 块大小为 `2^k` 页；`Page.property` 存阶，仅块头 `PG_property=1`。
- 建图：`init_memmap` 将 `[base,n)` 按对齐从高到低贪心聚合进相应阶桶。
- 分配：`need=ceil_log2(n)`；若更高阶存在块，取出后逐阶二分拆分到 need，将右半块回收到对应桶。
- 释放：按对齐与剩余量选择最大可能阶为单位归还，逐阶查询伙伴块（按物理页号异或 `2^k`），若同阶空闲则合并并提升阶，直至无法合并或达上界。
- 复杂度：近似 O(MAX_ORDER)。

测试：提供 `buddy_check()`，可通过 `-DBUDDY_SELF_TEST` 在 `pmm_init` 尾部触发，串口输出含 “buddy_check() succeeded!”。
Buddy System算法把系统中的可用存储空间划分为存储块(Block)来进行管理, 每个存储块的大小必须是2的n次幂(Pow(2, n)), 即1, 2, 4, 8, 16, 32, 64, 128...

 -  参考[伙伴分配器的一个极简实现](http://coolshell.cn/articles/10427.html)， 在ucore中实现buddy system分配算法，要求有比较充分的测试用例说明实现的正确性，需要有设计文档。
 
#### 扩展练习Challenge：任意大小的内存单元slub分配算法（需要编程）
实现位置 `kern/mm/slub.{h,c}`。设计要点：
- size-class：16/32/64/128/256/512/1024/2048/4096 字节；>4096 直接整页分配。
- slab：一页承载 header+位图+对象区；位图按 32bit 词管理空闲对象。
- 列表：每个 cache 维护 empty/partial/full 三类 slab；分配优先 partial，其次 empty，不足则新建 slab；释放对象后若 slab 为空则归还整页。

测试：提供 `slub_check()` 自测，`-DSLUB_SELF_TEST` 触发，串口输出含 “slub_check() succeeded!”。
slub算法，实现两层架构的高效内存单元分配，第一层是基于页大小的内存分配，第二层是在第一层基础上实现基于任意大小的内存分配。可简化实现，能够体现其主体思想即可。

 - 参考[linux的slub分配算法/](http://www.ibm.com/developerworks/cn/linux/l-cn-slub/)，在ucore中实现slub分配算法。要求有比较充分的测试用例说明实现的正确性，需要有设计文档。

#### 扩展练习Challenge：硬件的可用物理内存范围的获取方法（思考题）
  - 如果 OS 无法提前知道当前硬件的可用物理内存范围，请问你有何办法让 OS 获取可用物理内存范围？

可行途径：
- RISC-V: 通过设备树 DTB 读取 `memory` 节点（本实验使用 `get_memory_base/size`），或通过固件(OpenSBI)暴露的 SBI 调用。
- x86: BIOS E820 内存映射表、UEFI 内存映射、ACPI SRAT/SLIT 等。
- ARM: 设备树/ACPI 提供的 `memory`/reserved 区域；引导加载器传参（如 U-Boot）。

需结合保留区（内核、设备 MMIO、固件）过滤后形成可分配物理内存区间。

与参考答案的区别：
- 默认 PMM 采用 Best-Fit 并扩展正则校验 satp 输出；新增 Buddy/SLUB 两套实现与独立评分脚本；在页级实现 Buddy 的阶聚合与伙伴合并，以及 SLUB 的位图对象管理。

重要知识点：
- 连续物理页分配（FF/BF）：空闲链表管理、切割/合并策略、外碎片控制。
- 伙伴系统：阶制块、伙伴定位、对齐与合并逻辑。
- SLUB：size-class、slab 生命周期、位图/空闲对象管理、页级委托。
- 硬件内存发现：DTB/E820/SBI/UEFI/ACPI 等机制与保留区处理。


> Challenges是选做，完成Challenge的同学可单独提交Challenge。完成得好的同学可获得最终考试成绩的加分。