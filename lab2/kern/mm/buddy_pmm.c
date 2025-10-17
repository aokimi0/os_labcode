#include <pmm.h>
#include <list.h>
#include <string.h>
#include <buddy_pmm.h>
#include <stdio.h>

/*
 * Buddy System 简化实现说明（按页框粒度）：
 *
 * - 维护每阶(0..MAX_ORDER)空闲链表，阶k表示块大小为 2^k 页。
 * - struct Page.property 存阶，仅块头页 PG_property=1。
 * - init_memmap：将 n 页从 base 起，按尽量大的 2^k 聚合入桶，地址有序并 2^k 对齐。
 * - alloc_pages(n)：计算 need_order = ceil_log2(n)，若对应或更高阶有块，则逐阶向下拆分到 need_order。
 * - free_pages(base,n)：按 need_order 聚合后逐阶向上合并伙伴块（物理连续且伙伴头 PG_property=1 且同阶）。
 * - 复杂度：分配/释放 O(MAX_ORDER)。
 */

#define MAX_ORDER  16  // 支持最大 2^(16) 页 = 256MiB，在本实验内足够

typedef struct {
    list_entry_t free_list;
    unsigned int nr_free;
} order_list_t;

static order_list_t buddy_area[MAX_ORDER + 1];
static size_t total_free_pages;

#define bucket_list(k)      (buddy_area[(k)].free_list)
#define bucket_nr_free(k)   (buddy_area[(k)].nr_free)

static inline size_t order_block_pages(unsigned int order) {
    return (size_t)1U << order;
}

static inline unsigned int floor_log2(size_t n) {
    unsigned int r = 0;
    while ((size_t)1 << (r + 1) <= n) r++;
    return r;
}

static inline unsigned int ceil_log2(size_t n) {
    unsigned int f = floor_log2(n);
    return ((size_t)1U << f) == n ? f : (f + 1);
}

static inline uintptr_t page_addr(struct Page *p) { return page2pa(p); }

static inline int is_aligned(struct Page *p, unsigned int order) {
    return ((page_addr(p) >> PGSHIFT) & (order_block_pages(order) - 1)) == 0;
}

static inline struct Page *buddy_of(struct Page *p, unsigned int order) {
    size_t blk_pages = order_block_pages(order);
    size_t idx = page2ppn(p);
    size_t buddy_idx = idx ^ blk_pages;
    return &pages[buddy_idx - nbase];
}

static void buddy_init(void) {
    for (unsigned int k = 0; k <= MAX_ORDER; k++) {
        list_init(&bucket_list(k));
        bucket_nr_free(k) = 0;
    }
    total_free_pages = 0;
}

static void buddy_insert(struct Page *base, unsigned int order) {
    base->property = order; // 使用 property 存阶
    SetPageProperty(base);
    list_add(&bucket_list(order), &(base->page_link));
    bucket_nr_free(order) += order_block_pages(order);
    total_free_pages += order_block_pages(order);
}

static void buddy_remove(struct Page *base, unsigned int order) {
    list_del(&(base->page_link));
    ClearPageProperty(base);
    bucket_nr_free(order) -= order_block_pages(order);
    total_free_pages -= order_block_pages(order);
}

static void buddy_init_memmap(struct Page *base, size_t n) {
    assert(n > 0);
    // 清理页头状态
    for (struct Page *p = base; p != base + n; p++) {
        assert(PageReserved(p));
        p->flags = 0;
        set_page_ref(p, 0);
        ClearPageProperty(p);
    }

    // 贪心从高阶到低阶聚合，要求地址对齐 2^k
    size_t remain = n;
    struct Page *cur = base;
    while (remain > 0) {
        unsigned int max_fit = floor_log2(remain);
        // 限制对齐：找到不超过对齐要求的阶
        unsigned int k = max_fit;
        while (k > 0 && !is_aligned(cur, k)) k--;
        buddy_insert(cur, k);
        cur += order_block_pages(k);
        remain -= order_block_pages(k);
    }
}

static struct Page *buddy_alloc_pages(size_t n) {
    assert(n > 0);
    if (n > total_free_pages) {
        return NULL;
    }
    unsigned int need = ceil_log2(n);
    if (need > MAX_ORDER) return NULL;

    // 找到 >=need 的最小非空阶
    unsigned int k = need;
    while (k <= MAX_ORDER && list_empty(&bucket_list(k))) k++;
    if (k > MAX_ORDER) return NULL;

    // 取出一个块，并向下拆分直到 need
    list_entry_t *le = list_next(&bucket_list(k));
    struct Page *block = le2page(le, page_link);
    buddy_remove(block, k);

    while (k > need) {
        k--;
        struct Page *right = block + order_block_pages(k);
        buddy_insert(right, k);
        // 左块继续向下拆
    }

    // 现在 block 覆盖 2^need 页。需要精确满足 n 页：
    // 将尾部多余的 r = 2^need - n 页按 2^t 分块回收到桶。
    size_t blk_pages = order_block_pages(need);
    if (n < blk_pages) {
        struct Page *rest = block + n;
        size_t rem = blk_pages - n;
        while (rem > 0) {
            unsigned int tk = floor_log2(rem);
            // 对齐约束：rest 必须按 2^tk 对齐
            while (tk > 0 && !is_aligned(rest, tk)) tk--;
            buddy_insert(rest, tk);
            size_t s = order_block_pages(tk);
            rest += s;
            rem -= s;
        }
        // total_free_pages 已通过 insert 增加了 (blk_pages - n)，净减少 n
    }

    ClearPageProperty(block);
    return block;
}

static void buddy_free_pages(struct Page *base, size_t n) {
    assert(n > 0);
    // 标准做法：按需要阶聚合，以 2^k 页块逐块归还并合并
    size_t remain = n;
    struct Page *cur = base;
    while (remain > 0) {
        unsigned int k = 0;
        // 受对齐限制的最大可合并阶
        while (k + 1 <= MAX_ORDER && is_aligned(cur, k + 1) && order_block_pages(k + 1) <= remain) {
            k++;
        }

        // 逐阶向上尝试合并伙伴
        while (k < MAX_ORDER) {
            struct Page *bd = buddy_of(cur, k);
            // 伙伴必须是同阶空闲块头
            int found = 0;
            if (PageProperty(bd) && bd->property == k) {
                // 在对应桶中删去伙伴
                list_entry_t *pos = &bucket_list(k);
                list_entry_t *it;
                while ((it = list_next(pos)) != &bucket_list(k)) {
                    if (le2page(it, page_link) == bd) {
                        found = 1;
                        list_del(it);
                        ClearPageProperty(bd);
                        bucket_nr_free(k) -= order_block_pages(k);
                        total_free_pages -= order_block_pages(k);
                        break;
                    }
                    pos = it;
                }
            }
            if (!found) break;
            // 规范化：更小地址作为新块头
            if (bd < cur) cur = bd;
            k++;
        }
        // 插入最终阶块
        cur->property = k;
        SetPageProperty(cur);
        list_add(&bucket_list(k), &(cur->page_link));
        bucket_nr_free(k) += order_block_pages(k);
        total_free_pages += order_block_pages(k);

        cur += order_block_pages(k);
        remain -= order_block_pages(k);
    }
}

static size_t buddy_nr_free_pages(void) { return total_free_pages; }

static void basic_check(void) {
    struct Page *p0, *p1, *p2;
    p0 = p1 = p2 = NULL;
    assert((p0 = alloc_page()) != NULL);
    assert((p1 = alloc_page()) != NULL);
    assert((p2 = alloc_page()) != NULL);
    assert(p0 != p1 && p0 != p2 && p1 != p2);
    free_page(p0); free_page(p1); free_page(p2);
}

void buddy_check(void) {
    // 简单分配/释放与合并验证
    size_t before = nr_free_pages();
    struct Page *a = alloc_pages(3); // 需要阶=2，实际分配 4 页
    assert(a != NULL);
    struct Page *b = alloc_pages(4);
    assert(b != NULL);
    free_pages(a, 3); // 以 3 页释放，逻辑将按对齐拆分+合并处理
    free_pages(b, 4);
    assert(nr_free_pages() >= before);
    cprintf("buddy_check() succeeded!\n");
}

static void buddy_check_wrapper(void) {
    // 与 default/best_fit 的 check 风格对齐
    basic_check();
}

const struct pmm_manager buddy_pmm_manager = {
    .name = "buddy_pmm_manager",
    .init = buddy_init,
    .init_memmap = buddy_init_memmap,
    .alloc_pages = buddy_alloc_pages,
    .free_pages = buddy_free_pages,
    .nr_free_pages = buddy_nr_free_pages,
    .check = buddy_check_wrapper,
};


