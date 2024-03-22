/*
 * printk() for use before the final page tables are setup.
 *
 * Copyright (C) 2012 Citrix Systems, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */
#ifndef __ARM_EARLY_PRINTK_H__
#define __ARM_EARLY_PRINTK_H__

#include <xen/page-size.h>
#include <asm/fixmap.h>

//#ifdef CONFIG_EARLY_PRINTK

/* need to add the uart address offset in page to the fixmap address */
/* #define FIXMAP_ADDR(n)  (FIXMAP_VIRT_START + (n) * PAGE_SIZE) */
/* 
    FIXMAP_VIRT_START ==> 0x20000400000
    #define FIXMAP_CONSOLE  0  /* The primary UART
    CONFIG_EARLY_UART_BASE_ADDRESS=0xff1a0000
    FIXMAP_ADDR(n) ==> 0x20000400000 + n * 4K

    EARLY_UART_VIRTUAL_ADDRESS ==> (FIXMAP_ADDR(FIXMAP_CONSOLE) + (CONFIG_EARLY_UART_BASE_ADDRESS & ~PAGE_MASK)) 
                                   ((FIXMAP_VIRT_START + (FIXMAP_CONSOLE) * PAGE_SIZE) + (CONFIG_EARLY_UART_BASE_ADDRESS & ~PAGE_MASK)) 
                                   ((0x20000400000 + 0 * 4K) + (0xff1a0000 & 0xfffffffffffff000)) 
                                   0x20000400000 + 0xff1a0000 ==> 0x200FF5A0000
*/
#define EARLY_UART_VIRTUAL_ADDRESS \
    (FIXMAP_ADDR(FIXMAP_CONSOLE) + (CONFIG_EARLY_UART_BASE_ADDRESS & ~PAGE_MASK))

//#endif /* !CONFIG_EARLY_PRINTK */

#endif
