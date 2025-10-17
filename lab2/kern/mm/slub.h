#ifndef __KERN_MM_SLUB_H__
#define __KERN_MM_SLUB_H__

#include <defs.h>

/*
 * 简化 SLUB 接口：页级由 PMM 提供，SLUB 仅负责小对象分配。
 */

void slub_init(void);
void *kmalloc(size_t size);
void kfree(void *ptr);
void slub_check(void);

#endif /* !__KERN_MM_SLUB_H__ */


