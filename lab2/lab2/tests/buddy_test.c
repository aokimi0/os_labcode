#include <pmm.h>
#include <stdio.h>

void buddy_check(void);

void buddy_test_entry(void) {
    cprintf("[buddy_test] begin\n");
    buddy_check();
    cprintf("[buddy_test] end\n");
}



