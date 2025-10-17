#ifndef __KERN_MM_BUDDY_PMM_H__
#define __KERN_MM_BUDDY_PMM_H__

#include <pmm.h>

/*
 * Buddy System 分配器接口
 *
 * - 提供与 pmm_manager 一致的接口，作为可选物理页分配器。
 * - 约定：Page.property 存储阶数（order），仅块头页设置 PG_property。
 */

extern const struct pmm_manager buddy_pmm_manager;

/*
 * buddy_check
 *
 * 用于自测的简单一致性检查，通过 -DBUDDY_SELF_TEST 在 pmm_init 末尾触发。
 */
void buddy_check(void);

#endif /* !__KERN_MM_BUDDY_PMM_H__ */


