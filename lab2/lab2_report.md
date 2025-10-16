# 物理内存与页表
金莫迪，李星宇，廖望

## 练习一
### 设计实现过程分析

`First-Fit`（首次适应）算法是一种动态内存分配算法。其核心思想是，当需要分配内存时，从头开始遍历空闲内存块链表，并选择第一个大小足够满足请求的空闲块进行分配。如果这个块比请求的大小要大，就将其分割成两部分：一部分用于满足请求，另一部分（剩余部分）作为一个新的、更小的空闲块保留在链表中。

我的分析是基于 `kern/mm/default_pmm.c` 中的代码实现。该实现通过一个名为 `free_area_t` 的结构体来管理所有空闲的物理内存。这个结构体包含两个核心部分：

- `list_entry_t free_list`：一个双向链表的头结点。所有空闲的内存块都通过 `Page` 结构中的 `page_link` 成员链接到这个链表上。为了方便合并操作，这个链表始终保持按物理地址**从低到高**的顺序。
- `unsigned int nr_free`：一个计数器，记录当前所有空闲页的总数。
好的，没问题。你写的分析已经非常到位了，只是 Markdown 格式有些混乱。

我已经帮你重新整理和排版，修复了代码块的格式，并将对应的代码片段清晰地置于每一步的描述之下，使整个分析过程更具可读性。

-----

### **核心函数作用分析**

#### 1\. **`default_init(void)`**

  * **作用**：初始化物理内存管理器。
  * **过程描述**：
    1.  调用 `list_init(&free_list)`，将 `free_list` 链表头初始化为一个空的双向循环链表（即其 `next` 和 `prev` 指针都指向自身）。
    2.  将 `nr_free`（全局空闲页计数器）清零。

#### 2\. **`default_init_memmap(struct Page *base, size_t n)`**

  * **作用**：将一段探测到的、可用的物理内存区域添加到 `free_list` 中。
  * **过程描述**：
    1.  函数接收一个 `Page` 结构数组的基地址 `base` 和页面数量 `n`。首先进行合法性断言。
        ```c
        assert(n > 0);
        ```
    2.  遍历这 `n` 个 `Page` 结构，将它们的 `flags` 和 `property` 清零，并设置引用计数 `ref` 为0，确保它们处于一个干净的“空闲”状态。
        ```c
        struct Page *p = base;
        for (; p != base + n; p ++) {
            assert(PageReserved(p));
            p->flags = p->property = 0;
            set_page_ref(p, 0);
        }
        ```
    3.  设置块头信息：
          * `base->property = n;`：将整个连续空闲块的大小 `n` 存储在**这个块的第一个 `Page` 结构**的 `property` 成员中。
          * `SetPageProperty(base)`：将第一个页的标志位设置为 `PG_property`，表示这是一个空闲块的起始页。
          * `nr_free += n;`：更新全局空闲页计数。
        <!-- end list -->
        ```c
        base->property = n;
        SetPageProperty(base);
        nr_free += n;
        ```
    4.  最后，将这个新的空闲块（由 `base` 代表）按**物理地址有序**地插入到全局 `free_list` 链表中。它通过遍历链表找到第一个地址比 `base` 大的空闲块，然后将 `base` 插入到它的前面；如果 `base` 的地址最大，则插入到链表末尾。
        ```c
        if (list_empty(&free_list)) {
            list_add(&free_list, &(base->page_link));
        } else {
            list_entry_t* le = &free_list;
            while ((le = list_next(le)) != &free_list) {
                struct Page* page = le2page(le, page_link);
                if (base < page) {
                    list_add_before(le, &(base->page_link));
                    break;
                } else if (list_next(le) == &free_list) {
                    list_add(le, &(base->page_link));
                    break; // 修正：插入后应退出循环
                }
            }
        }
        ```

#### 3\. **`default_alloc_pages(size_t n)`**

  * **作用**：实现 First-Fit 算法的核心逻辑，从 `free_list` 中分配 `n` 个连续的物理页。
  * **过程描述**：
    1.  首先进行合法性检查，如果请求的 `n` 大于总空闲页数 `nr_free`，则说明内存不足，直接返回 `NULL`。
        ```c
        assert(n > 0);
        if (n > nr_free) {
            return NULL;
        }
        ```
    2.  **遍历查找**：从 `free_list` 的头部开始，循环遍历每一个空闲块，查找**第一个**大小 (`p->property`) 大于或等于 `n` 的块。
        ```c
        struct Page *page = NULL;
        list_entry_t *le = &free_list;
        while ((le = list_next(le)) != &free_list) {
            struct Page *p = le2page(le, page_link);
            if (p->property >= n) {
                page = p;
                break;
            }
        }
        ```
    3.  **执行分配与分割**：如果找到了合适的块 (`page != NULL`)，先将这个找到的块从 `free_list` 中移除。如果找到的块比需要的大 (`page->property > n`)，则将剩余部分构造成一个新的空闲块，并将其插回到原先的位置。再更新全局空闲页数 `nr_free`，并清除被分配块的 `PG_property` 标志位。
        <!-- end list -->
        ```c
        if (page != NULL) {
            list_entry_t* prev = list_prev(&(page->page_link));
            list_del(&(page->page_link));
            if (page->property > n) {
                struct Page *p = page + n;
                p->property = page->property - n;
                SetPageProperty(p);
                list_add(prev, &(p->page_link));
            }
            nr_free -= n;
            ClearPageProperty(page);
        }
        ```
    4.  最后返回分配到的块的起始页 `page` 的指针。如果未找到，则返回 `NULL`。
        ```c
        return page;
        ```

#### 4\. **`default_free_pages(struct Page *base, size_t n)`**

  * **作用**：释放从 `base` 开始的 `n` 个连续物理页，并将它们归还给 `free_list`，同时尝试与相邻的空闲块进行**合并**。
  * **过程描述**：
    1.  首先，将要释放的 `n` 个页的状态重置为空闲状态，并设置好新空闲块的块头信息 (`base->property = n`)。
        ```c
        assert(n > 0);
        struct Page *p = base;
        for (; p != base + n; p ++) {
            assert(!PageReserved(p) && !PageProperty(p));
            p->flags = 0;
            set_page_ref(p, 0);
        }
        base->property = n;
        SetPageProperty(base);
        nr_free += n;
        ```
    2.  将这个新形成的空闲块按地址有序地插入到 `free_list` 中。
        ```c
        // 插入逻辑与 default_init_memmap 类似
        if (list_empty(&free_list)) {
            list_add(&free_list, &(base->page_link));
        } else {
            list_entry_t* le = &free_list;
            while ((le = list_next(le)) != &free_list) {
                struct Page* page = le2page(le, page_link);
                if (base < page) {
                    list_add_before(le, &(base->page_link));
                    break;
                } else if (list_next(le) == &free_list) {
                    list_add(le, &(base->page_link));
                    break; // 修正：插入后应退出循环
                }
            }
        }
        ```
    3.  合并操作：此步可以减少外部碎片，分向前合并和向后合并两步。
          * 向前合并：检查新块前一个空闲块的末尾是否与新块的开头物理地址连续。如果是，则将它们合并成一个更大的块。
            ```c
            list_entry_t* le = list_prev(&(base->page_link));
            if (le != &free_list) {
                p = le2page(le, page_link);
                if (p + p->property == base) {
                    p->property += base->property;
                    ClearPageProperty(base);
                    list_del(&(base->page_link));
                    base = p; // 合并后，新的块头变为前一个块
                }
            }
            ```
          * 向后合并：检查当前块（可能已经向前合并过）的末尾是否与后一个空闲块的开头物理地址连续。如果是，则再次合并。
            ```c
            le = list_next(&(base->page_link));
            if (le != &free_list) {
                p = le2page(le, page_link);
                if (base + base->property == p) {
                    base->property += p->property;
                    ClearPageProperty(p);
                    list_del(&(p->page_link));
                }
            }
            ```
### **思考题：你的 First-Fit 算法是否有进一步的改进空间？**

是的，当前实现的 First-Fit 算法存在一些可以改进的空间，主要集中在**性能**和**碎片化**两个方面。

1.  **性能改进：Next-Fit 算法**
    * **问题**：当前的 First-Fit 实现每次分配都从 `free_list` 的头部开始扫描。这会导致链表头部的区域被反复切割，留下许多小的、难以利用的碎片，并且每次分配小内存时都可能需要跳过这些小碎片，增加了搜索时间。
    * **改进方案**：可以实现 **Next-Fit** 算法。引入一个全局的“上一次查找结束位置”的指针。下一次分配请求到来时，从这个指针指向的位置开始向后搜索，而不是从链表头开始。当搜索到链表末尾时，再回到链表头继续搜索。
    * **优点**：这种方式使得内存的消耗和碎片在整个空闲链表中分布得更均匀，并且在很多情况下可以减少平均搜索长度。

2. **优化数据结构：提升释放与合并的效率**
* **当前实现的问题**：`default_free_pages` 函数为了实现相邻块的合并，必须维持 `free_list` 按物理地址有序。这意味着每次释放内存时，都需要线性扫描（O(N)）`free_list` 来找到正确的插入位置。当系统中的空闲块数量（N）非常大时，释放内存的操作会变得很慢。
* **改进方案**：用一个更高效的、支持排序的数据结构来替代简单的双向链表，例如自平衡二叉搜索树（如红黑树）。
* **实现**：
    1. 使用红黑树来组织所有空闲块，树的节点按空闲块的物理起始地址进行排序。
    2. 释放时 `free_pages`：在树中查找新释放块的地址，可以在 O(log N) 时间内完成。通过这次查找，可以立即定位到它在地址上的前驱和后继节点，从而高效地进行合并检查和节点操作。
    3. 分配时 `alloc_pages`：为了严格遵循 First-Fit（最低地址优先）的原则，需要从树的最小节点（最左侧叶子节点）开始进行中序遍历，直到找到满足条件的块。虽然查找的复杂度没有降低，但释放操作的效率得到了质的提升。

* **效果**：在内存分配和释放都非常频繁的系统中，将释放操作的耗时从 O(N) 降低到 O(log N) 可以带来显著的整体性能改善。
3.  **数据结构改进：多级空闲链表**
    * **问题**：当系统中存在大量空闲块时，单一的链表线性扫描 O(N) 的效率非常低。
    * **改进方案**：使用多级空闲链表，也叫分离适配。我们可以根据空闲块的大小来组织它们。例如，创建一个链表数组 `free_list[i]`，其中 `free_list[0]` 存放大小为1的块，`free_list[1]` 存放大小为2的块，`free_list[2]` 存放大小为3-4的块，`free_list[3]` 存放大小为5-8的块，以此类推。
    * **优点**：当需要分配大小为 `n` 的内存时，可以直接去对应的链表中查找，大大提高了查找效率，时间复杂度接近 O(1)。Linux 内核中的 **伙伴系统 (Buddy System)** 和 **Slab 分配器** 就是基于这种思想的更精妙的实现。

---
