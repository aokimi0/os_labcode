#include <slub.h>
#include <pmm.h>
#include <list.h>
#include <string.h>
#include <stdio.h>

/*
 * 简化版 SLUB：
 * - 预定义 size-classes：16,32,64,128,256,512,1024,2048,4096。
 * - 每个 slab 由整页提供，内部切分为等大对象，使用位图跟踪空闲。
 * - 当对象数为0时释放该页。
 */

typedef struct slab_header {
    list_entry_t link;      // 链入 kmem_cache 的 partial/empty 列表
    uint16_t obj_size;      // 对象大小
    uint16_t capacity;      // 总对象个数
    uint16_t used;          // 已分配个数
    uint16_t bitmap_words;  // 位图以 32bit 词为单位
    uint32_t bitmap[];      // 变长位图
} slab_header_t;

typedef struct kmem_cache {
    uint16_t obj_size;
    list_entry_t partial;
    list_entry_t full;
    list_entry_t empty;
} kmem_cache_t;

static const size_t k_size_classes[] = {16,32,64,128,256,512,1024,2048,4096};
static kmem_cache_t caches[sizeof(k_size_classes)/sizeof(k_size_classes[0])];

static int size_to_index(size_t sz) {
    for (size_t i = 0; i < sizeof(k_size_classes)/sizeof(k_size_classes[0]); i++) {
        if (sz <= k_size_classes[i]) return (int)i;
    }
    return -1;
}

static inline void *page_to_va(struct Page *p) {
    return (void *)(page2pa(p) + va_pa_offset);
}

static slab_header_t *new_slab(kmem_cache_t *cache) {
    struct Page *pg = alloc_pages(1);
    if (!pg) return NULL;
    void *va = page_to_va(pg);
    memset(va, 0, PGSIZE);
    // 计算位图与容量
    size_t obj_size = cache->obj_size;
    size_t max_objs = (PGSIZE - sizeof(slab_header_t)) / (obj_size + 0); // 简化：位图单独估算
    // 估算位图词数：向上取整(max_objs/32)
    size_t words = (max_objs + 31) / 32;
    // 调整 capacity 使 header+bitmap+objects 不超过一页
    while (sizeof(slab_header_t) + words * sizeof(uint32_t) + max_objs * obj_size > PGSIZE) {
        if (max_objs == 0) return NULL;
        max_objs--;
        words = (max_objs + 31) / 32;
    }
    slab_header_t *hdr = (slab_header_t *)va;
    hdr->obj_size = (uint16_t)obj_size;
    hdr->capacity = (uint16_t)max_objs;
    hdr->used = 0;
    hdr->bitmap_words = (uint16_t)words;
    list_init(&hdr->link);
    list_add(&cache->empty, &hdr->link);
    return hdr;
}

// 手动实现 count trailing zeros，避免链接 libgcc
static inline int ctz32(uint32_t x) {
    if (x == 0) return 32;
    int n = 0;
    while ((x & 1) == 0) {
        x >>= 1;
        n++;
    }
    return n;
}

static void *alloc_from_slab(slab_header_t *hdr) {
    // 在位图中找第一个0位
    for (uint16_t w = 0; w < hdr->bitmap_words; w++) {
        uint32_t mask = hdr->bitmap[w];
        if (mask != 0xFFFFFFFFu) {
            uint32_t inv = ~mask;
            int bit = ctz32(inv);
            uint32_t setmask = 1u << bit;
            hdr->bitmap[w] |= setmask;
            hdr->used++;
            uint32_t idx = (uint32_t)w * 32u + (uint32_t)bit;
            if (idx >= hdr->capacity) break;
            // 计算对象起始地址：header + bitmap + 对象区
            uint8_t *base = (uint8_t *)hdr;
            uint8_t *obj_base = base + sizeof(slab_header_t) + hdr->bitmap_words * sizeof(uint32_t);
            return obj_base + (size_t)idx * hdr->obj_size;
        }
    }
    return NULL;
}

static void free_to_slab(slab_header_t *hdr, void *ptr) {
    uint8_t *base = (uint8_t *)hdr;
    uint8_t *obj_base = base + sizeof(slab_header_t) + hdr->bitmap_words * sizeof(uint32_t);
    size_t diff = (uint8_t *)ptr - obj_base;
    size_t idx = diff / hdr->obj_size;
    size_t w = idx / 32, b = idx % 32;
    hdr->bitmap[w] &= ~(1u << b);
    hdr->used--;
}

void slub_init(void) {
    for (size_t i = 0; i < sizeof(k_size_classes)/sizeof(k_size_classes[0]); i++) {
        caches[i].obj_size = (uint16_t)k_size_classes[i];
        list_init(&caches[i].partial);
        list_init(&caches[i].full);
        list_init(&caches[i].empty);
    }
}

void *kmalloc(size_t size) {
    if (size == 0) return NULL;
    if (size > PGSIZE) {
        // 简化：页以上请求直接整页分配并返回内核虚拟地址
        size_t pages = (size + PGSIZE - 1) / PGSIZE;
        struct Page *pg = alloc_pages(pages);
        return pg ? (void *)(page2pa(pg) + va_pa_offset) : NULL;
    }
    int idx = size_to_index(size);
    if (idx < 0) return NULL;
    kmem_cache_t *cache = &caches[idx];

    // 1) partial 优先
    list_entry_t *le = &cache->partial;
    while ((le = list_next(le)) != &cache->partial) {
        slab_header_t *hdr = (slab_header_t *)((char *)le - offsetof(slab_header_t, link));
        void *p = alloc_from_slab(hdr);
        if (p) {
            if (hdr->used == hdr->capacity) {
                list_del(&hdr->link);
                list_add(&cache->full, &hdr->link);
            }
            return p;
        }
    }
    // 2) empty
    le = &cache->empty;
    while ((le = list_next(le)) != &cache->empty) {
        slab_header_t *hdr = (slab_header_t *)((char *)le - offsetof(slab_header_t, link));
        void *p = alloc_from_slab(hdr);
        if (p) {
            // 从 empty 移到 partial/full
            list_del(&hdr->link);
            if (hdr->used == hdr->capacity) {
                list_add(&cache->full, &hdr->link);
            } else {
                list_add(&cache->partial, &hdr->link);
            }
            return p;
        }
    }
    // 3) 新建 slab
    slab_header_t *hdr = new_slab(cache);
    if (!hdr) return NULL;
    void *p = alloc_from_slab(hdr);
    // 从 empty 移动
    list_del(&hdr->link);
    if (hdr->used == hdr->capacity) {
        list_add(&cache->full, &hdr->link);
    } else {
        list_add(&cache->partial, &hdr->link);
    }
    return p;
}

void kfree(void *ptr) {
    if (!ptr) return;
    // 通过页头推导 slab_header：页首即 header
    uintptr_t kva = (uintptr_t)ptr;
    uintptr_t pa = kva - va_pa_offset;
    uintptr_t page_pa = pa & ~((uintptr_t)PGSIZE - 1);
    struct Page *pg = pa2page(page_pa);
    slab_header_t *hdr = (slab_header_t *)((char *)(page2pa(pg) + va_pa_offset));
    // 释放对象
    size_t was_full = (hdr->used == hdr->capacity);
    free_to_slab(hdr, ptr);
    // 链位置调整
    if (hdr->used == 0) {
        // 释放整页
        list_del(&hdr->link);
        free_pages(pg, 1);
        return;
    }
    if (was_full) {
        // 从 full 移到 partial
        // 所属 cache 需要通过对象大小匹配
        for (size_t i = 0; i < sizeof(k_size_classes)/sizeof(k_size_classes[0]); i++) {
            if (caches[i].obj_size == hdr->obj_size) {
                list_add(&caches[i].partial, &hdr->link);
                break;
            }
        }
    }
}

void slub_check(void) {
    slub_init();
    void *a = kmalloc(24);
    void *b = kmalloc(24);
    void *c = kmalloc(2000);
    assert(a && b && c);
    kfree(a);
    kfree(b);
    kfree(c);
    cprintf("slub_check() succeeded!\n");
}


