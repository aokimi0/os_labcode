#include <pmm.h>
#include <slub.h>
#include <stdio.h>

void slub_test_entry(void) {
    cprintf("[slub_test] begin\n");
    slub_check();
    cprintf("[slub_test] end\n");
}



