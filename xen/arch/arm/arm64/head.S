/*
 * xen/arch/arm/head.S
 *
 * Start-of-day code for an ARMv8.
 *
 * Ian Campbell <ian.campbell@citrix.com>
 * Copyright (c) 2012 Citrix Systems.
 *
 * Based on ARMv7-A head.S by
 * Tim Deegan <tim@xen.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include <asm/page.h>
#include <asm/early_printk.h>
#include <efi/efierr.h>
#include <asm/arm64/efibind.h>

#define PT_PT     0xf7f /* nG=1 AF=1 SH=11 AP=01 NS=1 ATTR=111 T=1 P=1 */ 
#define PT_MEM    0xf7d /* nG=1 AF=1 SH=11 AP=01 NS=1 ATTR=111 T=0 P=1 */
#define PT_MEM_L3 0xf7f /* nG=1 AF=1 SH=11 AP=01 NS=1 ATTR=111 T=1 P=1 */
#define PT_DEV    0xe71 /* nG=1 AF=1 SH=10 AP=01 NS=1 ATTR=100 T=0 P=1 */
#define PT_DEV_L3 0xe73 /* nG=1 AF=1 SH=10 AP=01 NS=1 ATTR=100 T=1 P=1 */

/* Convenience defines to get slot used by Xen mapping. */
/* #define zeroeth_table_offset(va)  TABLE_OFFSET(zeroeth_linear_offset(va))  */
/* #define zeroeth_linear_offset(va) ((va) >> ZEROETH_SHIFT) */
/* #define TABLE_OFFSET(offs) (_AT(unsigned int, offs) & XEN_PT_LPAE_ENTRY_MASK) */
/* XEN_ZEROETH_SLOT ==> zeroeth_table_offset(0x20000200000)  */
/*                  ==> TABLE_OFFSET(zeroeth_linear_offset(0x20000200000)) */
/*                  ==> TABLE_OFFSET((0x20000200000 >> 39)) */
/*                  ==> TABLE_OFFSET(4)                     */
/*                  ==> (_AT(unsigned int, 4) & XEN_PT_LPAE_ENTRY_MASK)*/
/*                  ==> (4 & XEN_PT_LPAE_ENTRY_MASK) */
/*                  ==> (4 & 0x1ff) ==> XEN_ZEROETH_SLOT = 4 */
#define XEN_ZEROETH_SLOT    zeroeth_table_offset(XEN_VIRT_START)
#define XEN_FIRST_SLOT      first_table_offset(XEN_VIRT_START)
#define XEN_SECOND_SLOT     second_table_offset(XEN_VIRT_START)

#define __HEAD_FLAG_PAGE_SIZE   ((PAGE_SHIFT - 10) / 2)

#define __HEAD_FLAG_PHYS_BASE   1

#define __HEAD_FLAGS            ((__HEAD_FLAG_PAGE_SIZE << 1) | \
                                 (__HEAD_FLAG_PHYS_BASE << 3))

#if defined(CONFIG_EARLY_PRINTK) && defined(CONFIG_EARLY_PRINTK_INC)
#include CONFIG_EARLY_PRINTK_INC
#endif

/*
 * Common register usage in this file:
 *  x0  -
 *  x1  -
 *  x2  -
 *  x3  -
 *  x4  -
 *  x5  -
 *  x6  -
 *  x7  -
 *  x8  -
 *  x9  -
 *  x10 -
 *  x11 -
 *  x12 -
 *  x13 -
 *  x14 -
 *  x15 -
 *  x16 -
 *  x17 -
 *  x18 -
 *  x19 - paddr(start)
 *  x20 - phys offset
 *  x21 - DTB address (boot cpu only)
 *  x22 -
 *  x23 - UART address
 *  x24 -
 *  x25 -
 *  x26 - skip_zero_bss (boot cpu only)
 *  x27 -
 *  x28 -
 *  x29 -
 *  x30 - lr
 */

#ifdef CONFIG_EARLY_PRINTK
/*
 * Macro to print a string to the UART, if there is one.
 *
 * Clobbers x0 - x3
 */
#define PRINT(_s)          \
        mov   x3, lr ;     \
        adr   x0, 98f ;    \
        bl    puts    ;    \
        mov   lr, x3 ;     \
        RODATA_STR(98, _s)

/*
 * Macro to print the value of register \xb
 *
 * Clobbers x0 - x4
 */
.macro print_reg xb
        mov   x0, \xb
        mov   x4, lr
        bl    putn
        mov   lr, x4
.endm

#else /* CONFIG_EARLY_PRINTK */
#define PRINT(s)

.macro print_reg xb
.endm

#endif /* !CONFIG_EARLY_PRINTK */

/*
 * Pseudo-op for PC relative adr <reg>, <symbol> where <symbol> is
 * within the range +/- 4GB of the PC.
 *
 * @dst: destination register (64 bit wide)
 * @sym: name of the symbol
 */
.macro  adr_l, dst, sym
        adrp \dst, \sym
        add  \dst, \dst, :lo12:\sym
.endm

/* Load the physical address of a symbol into xb */
/* x20 为链接地址 与 运行地址 之间的 offset，所有有了这个offset，那么就可以直接将符号的链接地址 算出对应的 运行时的物理地址了 */
.macro load_paddr xb, sym
        ldr \xb, =\sym
        add \xb, \xb, x20
.endm

        .section .text.header, "ax", %progbits
        /*.aarch64*/

        /*
         * Kernel startup entry point.
         * ---------------------------
         *
         * The requirements are:
         *   MMU = off, D-cache = off, I-cache = on or off,
         *   x0 = physical address to the FDT blob.
         *
         * This must be the very first address in the loaded image.
         * It should be linked at XEN_VIRT_START, and loaded at any
         * 4K-aligned address.  All of text+data+bss must fit in 2MB,
         * or the initial pagetable code below will need adjustment.
         */

GLOBAL(start)
        /*
         * DO NOT MODIFY. Image header expected by Linux boot-loaders.
         */
efi_head:
        /*
         * This add instruction has no meaningful effect except that
         * its opcode forms the magic "MZ" signature of a PE/COFF file
         * that is required for UEFI applications.
         */
        add     x13, x18, #0x16
        b       real_start           /* branch to kernel start */
        .quad   0                    /* Image load offset from start of RAM */
        .quad   _end - start         /* Effective size of kernel image, little-endian */
        .quad   __HEAD_FLAGS         /* Informative flags, little-endian */
        .quad   0                    /* reserved */
        .quad   0                    /* reserved */
        .quad   0                    /* reserved */
        .byte   0x41                 /* Magic number, "ARM\x64" */
        .byte   0x52
        .byte   0x4d
        .byte   0x64
        .long   pe_header - efi_head        /* Offset to the PE header. */

        /*
         * Add the PE/COFF header to the file.  The address of this header
         * is at offset 0x3c in the file, and is part of Linux "Image"
         * header.  The arm64 Linux Image format is designed to support
         * being both an 'Image' format binary and a PE/COFF binary.
         * The PE/COFF format is defined by Microsoft, and is available
         * from: http://msdn.microsoft.com/en-us/gg463119.aspx
         * Version 8.3 adds support for arm64 and UEFI usage.
         */

        .align  3
pe_header:
        .ascii  "PE"
        .short  0
coff_header:
        .short  0xaa64                          /* AArch64 */
        .short  2                               /* nr_sections */
        .long   0                               /* TimeDateStamp */
        .long   0                               /* PointerToSymbolTable */
        .long   1                               /* NumberOfSymbols */
        .short  section_table - optional_header /* SizeOfOptionalHeader */
        .short  0x206                           /* Characteristics. */
                                                /* IMAGE_FILE_DEBUG_STRIPPED | */
                                                /* IMAGE_FILE_EXECUTABLE_IMAGE | */
                                                /* IMAGE_FILE_LINE_NUMS_STRIPPED */
optional_header:
        .short  0x20b                           /* PE32+ format */
        .byte   0x02                            /* MajorLinkerVersion */
        .byte   0x14                            /* MinorLinkerVersion */
        .long   _end - real_start               /* SizeOfCode */
        .long   0                               /* SizeOfInitializedData */
        .long   0                               /* SizeOfUninitializedData */
        .long   efi_start - efi_head            /* AddressOfEntryPoint */
        .long   real_start - efi_head           /* BaseOfCode */

extra_header_fields:
        .quad   0                               /* ImageBase */
        .long   0x1000                          /* SectionAlignment (4 KByte) */
        .long   0x8                             /* FileAlignment */
        .short  0                               /* MajorOperatingSystemVersion */
        .short  0                               /* MinorOperatingSystemVersion */
        .short  0                               /* MajorImageVersion */
        .short  0                               /* MinorImageVersion */
        .short  0                               /* MajorSubsystemVersion */
        .short  0                               /* MinorSubsystemVersion */
        .long   0                               /* Win32VersionValue */

        .long   _end - efi_head                 /* SizeOfImage */

        /* Everything before the kernel image is considered part of the header */
        .long   real_start - efi_head           /* SizeOfHeaders */
        .long   0                               /* CheckSum */
        .short  0xa                             /* Subsystem (EFI application) */
        .short  0                               /* DllCharacteristics */
        .quad   0                               /* SizeOfStackReserve */
        .quad   0                               /* SizeOfStackCommit */
        .quad   0                               /* SizeOfHeapReserve */
        .quad   0                               /* SizeOfHeapCommit */
        .long   0                               /* LoaderFlags */
        .long   0x6                             /* NumberOfRvaAndSizes */

        .quad   0                               /* ExportTable */
        .quad   0                               /* ImportTable */
        .quad   0                               /* ResourceTable */
        .quad   0                               /* ExceptionTable */
        .quad   0                               /* CertificationTable */
        .quad   0                               /* BaseRelocationTable */

        /* Section table */
section_table:

        /*
         * The EFI application loader requires a relocation section
         * because EFI applications must be relocatable.  This is a
         * dummy section as far as we are concerned.
         */
        .ascii  ".reloc"
        .byte   0
        .byte   0                               /* end of 0 padding of section name */
        .long   0
        .long   0
        .long   0                               /* SizeOfRawData */
        .long   0                               /* PointerToRawData */
        .long   0                               /* PointerToRelocations */
        .long   0                               /* PointerToLineNumbers */
        .short  0                               /* NumberOfRelocations */
        .short  0                               /* NumberOfLineNumbers */
        .long   0x42100040                      /* Characteristics (section flags) */


        .ascii  ".text"
        .byte   0
        .byte   0
        .byte   0                               /* end of 0 padding of section name */
        .long   _end - real_start               /* VirtualSize */
        .long   real_start - efi_head           /* VirtualAddress */
        .long   __init_end_efi - real_start     /* SizeOfRawData */
        .long   real_start - efi_head           /* PointerToRawData */

        .long   0                /* PointerToRelocations (0 for executables) */
        .long   0                /* PointerToLineNumbers (0 for executables) */
        .short  0                /* NumberOfRelocations  (0 for executables) */
        .short  0                /* NumberOfLineNumbers  (0 for executables) */
        .long   0xe0500020       /* Characteristics (section flags) */
        .align  5
real_start:
        /* BSS should be zeroed when booting without EFI */
        mov   x26, #0                /* x26 := skip_zero_bss */

real_start_efi:
        msr   DAIFSet, 0xf           /* Disable all interrupts */

        /* Save the bootloader arguments in less-clobberable registers */
        mov   x21, x0                /* x21 := DTB, physical address  */

        /* Find out where we are */
        ldr   x0, =start     /* qemu gdb 打印出来的值是:x0=0x20000200000 ==> cat xen-syms.map ==> 0x20000200000 T start ==>  参考文档<0:【vygd】head.s中start标号值的分析 & “Find out where we are”源码分析>*/
        adr   x19, start     /* $x19=0x1f600000 ==> x19 := paddr (start) */
        sub   x20, x19, x0   /* $x20 = 0xfffffe001f400000 ==> x20 := phys-offset   */

        /* Using the DTB in the .dtb section? */
.ifnes CONFIG_DTB_FILE,""
        load_paddr x21, _sdtb
.endif

        /* Initialize the UART if earlyprintk has been enabled. */
#ifdef CONFIG_EARLY_PRINTK
        bl    init_uart
#endif
        PRINT("- Boot CPU booting -\r\n")

        bl    check_cpu_mode
        bl    cpu_init
        bl    create_page_tables
        load_paddr x0, boot_pgtable
        bl    enable_mmu

        /* We are still in the 1:1 mapping. Jump to the runtime Virtual Address. */
        ldr   x0, =primary_switched
        br    x0
primary_switched:
        /*
         * The 1:1 map may clash with other parts of the Xen virtual memory
         * layout. As it is not used anymore, remove it completely to
         * avoid having to worry about replacing existing mapping
         * afterwards.
         */
        bl    remove_identity_mapping
        bl    setup_fixmap
#ifdef CONFIG_EARLY_PRINTK
        /* Use a virtual address to access the UART. */
        ldr   x23, =EARLY_UART_VIRTUAL_ADDRESS
#endif
        bl    zero_bss
        PRINT("- Ready -\r\n")
        /* Setup the arguments for start_xen and jump to C world */
        mov   x0, x20                /* x0 := Physical offset */
        mov   x1, x21                /* x1 := paddr(FDT) */
        ldr   x2, =start_xen
        b     launch
ENDPROC(real_start)

GLOBAL(init_secondary)
        msr   DAIFSet, 0xf           /* Disable all interrupts */

        /* Find out where we are */
        ldr   x0, =start
        adr   x19, start             /* x19 := paddr (start) */
        sub   x20, x19, x0           /* x20 := phys-offset */

        mrs   x0, mpidr_el1
        ldr   x13, =(~MPIDR_HWID_MASK)
        bic   x24, x0, x13           /* Mask out flags to get CPU ID */

        /* Wait here until __cpu_up is ready to handle the CPU */
        load_paddr x0, smp_up_cpu
        dsb   sy
2:      ldr   x1, [x0]
        cmp   x1, x24
        beq   1f
        wfe
        b     2b
1:

#ifdef CONFIG_EARLY_PRINTK
        ldr   x23, =CONFIG_EARLY_UART_BASE_ADDRESS /* x23 := UART base address */
        PRINT("- CPU ")
        print_reg x24
        PRINT(" booting -\r\n")
#endif
        bl    check_cpu_mode
        bl    cpu_init
        load_paddr x0, init_ttbr
        ldr   x0, [x0]
        bl    enable_mmu

        /* We are still in the 1:1 mapping. Jump to the runtime Virtual Address. */
        ldr   x0, =secondary_switched
        br    x0
secondary_switched:
#ifdef CONFIG_EARLY_PRINTK
        /* Use a virtual address to access the UART. */
        ldr   x23, =EARLY_UART_VIRTUAL_ADDRESS
#endif
        PRINT("- Ready -\r\n")
        /* Jump to C world */
        ldr   x2, =start_secondary
        b     launch
ENDPROC(init_secondary)

/*
 * Check if the CPU has been booted in Hypervisor mode.
 * This function will never return when the CPU is booted in another mode
 * than Hypervisor mode.
 *
 * Clobbers x0 - x5
 */
check_cpu_mode:
        PRINT("- Current EL ")
        mrs   x5, CurrentEL /* 读取当前CPU所处的异常等级。下面并打印出来 */
        print_reg x5
        PRINT(" -\r\n")

        /* Are we in EL2 */  /* 这里会检测当前是否在EL2级别，如果不是的话，就跳到标号1处，进行异常退出了，看下下面的打印，XEN是一定要在EL2下运行的 */
        cmp   x5, #PSR_MODE_EL2t
        ccmp  x5, #PSR_MODE_EL2h, #0x4, ne
        b.ne  1f /* No */
        ret
1:
        /* OK, we're boned. */
        PRINT("- Xen must be entered in NS EL2 mode -\r\n") /* 这里有提示，下面也有提示，不在EL2的话，就是uboot bootloader的事情了，让他们修改好，或者qemu没有开启EL2 */
        PRINT("- Please update the bootloader -\r\n")
        b fail
ENDPROC(check_cpu_mode)

/*
 * Zero BSS
 *
 * Inputs:
 *   x26: Do we need to zero BSS?
 *
 * Clobbers x0 - x3
 */
zero_bss:
        /* Zero BSS only when requested */
        cbnz  x26, skip_bss

        PRINT("- Zero BSS -\r\n")
        ldr   x0, =__bss_start       /* x0 := vaddr(__bss_start) */
        ldr   x1, =__bss_end         /* x1 := vaddr(__bss_end)   */

1:      str   xzr, [x0], #8
        cmp   x0, x1
        b.lo  1b

skip_bss:
        ret
ENDPROC(zero_bss)

/*
 * Initialize the processor for turning the MMU on.
 *
 * Clobbers x0 - x3
 */
cpu_init:
        PRINT("- Initialize CPU -\r\n")

        /* Set up memory attribute type tables */
        ldr   x0, =MAIRVAL
        msr   mair_el2, x0

        /*
         * Set up TCR_EL2:
         * PS -- Based on ID_AA64MMFR0_EL1.PARange
         * Top byte is used
         * PT walks use Inner-Shareable accesses,
         * PT walks are write-back, write-allocate in both cache levels,
         * 48-bit virtual address space goes through this table.
         */
        ldr   x0, =(TCR_RES1|TCR_SH0_IS|TCR_ORGN0_WBWA|TCR_IRGN0_WBWA|TCR_T0SZ(64-48))
        /* ID_AA64MMFR0_EL1[3:0] (PARange) corresponds to TCR_EL2[18:16] (PS) */
        mrs   x1, ID_AA64MMFR0_EL1
        /* Limit to 48 bits, 256TB PA range (#5) */
        ubfm  x1, x1, #0, #3
        mov   x2, #5
        cmp   x1, x2
        csel  x1, x1, x2, lt

        bfi   x0, x1, #16, #3

        msr   tcr_el2, x0

        ldr   x0, =SCTLR_EL2_SET
        msr   SCTLR_EL2, x0
        isb

        /*
         * Ensure that any exceptions encountered at EL2
         * are handled using the EL2 stack pointer, rather
         * than SP_EL0.
         */
        msr spsel, #1
        ret
ENDPROC(cpu_init)

/*
 * Macro to find the slot number at a given page-table level
 *
 * slot:     slot computed
 * virt:     virtual address ==> 要映射的虚拟地址 
 * lvl:      page-table level
 */
/* UBFX <Rd>, <Rn>, #<lsb>, #<width> ==> unsigned int Rd = (Rn >> lsb) & ((1 << width) - 1); */
/* ubfx  \slot, \virt, #XEN_PT_LEVEL_SHIFT(\lvl), #XEN_PT_LPAE_SHIFT ==>  */
/* 《0:【vygd】XEN 宏 & 名词 解析【mfn pdx等】》 */
/* #define XEN_PT_LEVEL_SHIFT(lvl)  ==>((3 - lvl) * 9 + 12) ==> 最终是这个东东！！！ */
/*                                  ==> lvl:0 为 39 ==> 512G                       */
/*                                  ==> lvl:1 为 30 ==> 1G                         */
/*                                  ==> lvl:2 为 21 ==> 2M                         */
/*                                  ==> lvl:3 为 12 ==> 4K                         */
/* XEN_PT_LPAE_SHIFT ==> 9 ==> 9bit 就是512个entry的意思 ==> 每一级页表以512个entry(4K) 作为一级，后面的级别上 可能有多个4K页 */
/* 
ttbr0_el2 ==> |level0_entry0(4K or 512_entry)    ==> |level1_entry0(4K or 512_entry) ==>  |level2_entry0(4K or 512_entry)  ==>  |level3_entry0(4K or 512_entry) ==> include start paddr of 4K page 
              |                                      |                                    |                                     | ...
              |                                      |                                    |                                     |level3_entry511(4K or 512_entry) ==> include start paddr of 4K page 
              |                                      |                                    | ...
              |                                      |                                    |level2_entry512(4K or 512_entry)
              |                                      |    ....
              |                                      |level1_entry511(4K or 512_entry) ==> ...
              |           ....
              |level0_entry511(4K or 512_entry)  ==> |level1_entry0(4K or 512_entry) ==>  ...
                                                     |    ....
                                                     |level1_entry511(4K or 512_entry) ==>  ...
*/
/* lvl=0 ===> ubfx  \slot, \virt, #39, #9  ==> slot = (virt >> 39) & ((1 << 9) - 1) */
/* lvl=1 ===> ubfx  \slot, \virt, #30, #9  ==> slot = (virt >> 30) & ((1 << 9) - 1) */
/* lvl=2 ===> ubfx  \slot, \virt, #21, #9  ==> slot = (virt >> 21) & ((1 << 9) - 1) */
/* lvl=3 ===> ubfx  \slot, \virt, #12, #9  ==> slot = (virt >> 12) & ((1 << 9) - 1) */
.macro get_table_slot, slot, virt, lvl
        ubfx  \slot, \virt, #XEN_PT_LEVEL_SHIFT(\lvl), #XEN_PT_LPAE_SHIFT
.endm

/*
 * Macro to create a page table entry in \ptbl to \tbl
 *
 * ptbl:    table symbol where the entry will be created ==> 上级页表的地址 ==> ptbl 指向这级页表对应的数组 ==> uint64_t boot_pgtable[512] 
 * tbl:     table symbol to point to ==> 下级页表的地址
 * virt:    virtual address  ==> 待映射的虚拟地址 
 * lvl:     page-table level ==> 指定是第几级页表
 * tmp1:    scratch register ==> 临时要使用的寄存器
 * tmp2:    scratch register ==> 临时要使用的寄存器
 * tmp3:    scratch register ==> 临时要使用的寄存器
 *
 * Preserves \virt
 * Clobbers \tmp1, \tmp2, \tmp3
 *
 * Also use x20 for the phys offset.
 *
 * Note that all parameters using registers should be distinct.
 */
 /* 
    从下面函数的实现分析来看 ==> 为映射virt这个虚拟地址，要逐级填充各级页表的对应的entry 
    ==> 那么这里就是通过lvl来指定要填充的是第几级页表，ptbl指向这个要被填充的页表基地址，
    ==> 然后通过虚拟地址virt来索引该级页表的对应的entry
    ==> 这个entry中要填充 下一级页表的物理基地址(tbl) 以及相关的页表属性 
    通过virt + get_table_slot ==> 可以知道 要操作的是 第lvl级页表的entry的idx 
    这个entry里面要填充的内容：tbl的物理地址 + 对应的属性信息 ==> 存放在tmp3
    最后将上面的填充内容 写到 第lvl级页表(ptbl 指向这个第lvl级页表的数组的起始地址) 的某个entry(提取virt的某域段)
    然后后面逐级填充其他级别的页表 
  */
.macro create_table_entry, ptbl, tbl, virt, lvl, tmp1, tmp2, tmp3 
        /* get_table_slot 这个宏里面有很详细的对页表的说明 */
        /* get_table_slot 是找到 待映射的虚拟地址 在第lvl级页表的哪个entry ==> 结果存放在tmp1寄存器中 */
        /* 共4级, tmp1的值 ==> 要映射virt这个虚拟地址，那么在第lvl级页表中，对应的entry的idx，这个idx就存放在 tmp1 寄存器中 ==> 这个idx就叫做slot  */
        /* lvl=0 ===> ubfx  \slot, \virt, #39, #9  ==> slot = (virt >> 39) & ((1 << 9) - 1) */
        /* lvl=1 ===> ubfx  \slot, \virt, #30, #9  ==> slot = (virt >> 30) & ((1 << 9) - 1) */
        /* lvl=2 ===> ubfx  \slot, \virt, #21, #9  ==> slot = (virt >> 21) & ((1 << 9) - 1) */
        /* lvl=3 ===> ubfx  \slot, \virt, #12, #9  ==> slot = (virt >> 12) & ((1 << 9) - 1) */        
        get_table_slot \tmp1, \virt, \lvl   /* \tmp1 := slot in \tlb */

        /* load_paddr是得到符号的运行时的物理地址，方法是将符号的链接+offset ==> 运行时的phy_addr ==> offset是start起始阶段已经计算好的 链接地址与物理地址之间的偏移 */
        /* tmp2 中存放 tbl 这个符号的 运行时的物理地址 */
        load_paddr \tmp2, \tbl

        /* #define PT_PT     0xf7f ==>  nG=1 AF=1 SH=11 AP=01 NS=1 ATTR=111 T=1 P=1 ==>  也就是页表属性  */
        mov   \tmp3, #PT_PT                 /* \tmp3 := right for linear PT */
        /* ORR <Xd>, <Xn>, <Xm> ==>  Xd = Xn | Xm;  ==> 这些数据是后续 要填充到 对于级别页表的某个entry中去的 */
        /* tmp3寄存器里面存放的就是该页表的某个entry 要填充的内容 ==> 这个entry要填充的内容中 包含有 下级页表的物理地址, 也就是 tlb paddr，以及对应的属性信息 */
        orr   \tmp3, \tmp3, \tmp2           /*          + \tlb paddr */
        /* qemu 看真实的指令，发现下面指令最终用了两条指令来实现adr_l想要的功能 */
        /* 1： adrp x2, ptbl ==> 得到 ptbl 运行时 进行4K页对齐后的物理地址 ==> 比如这里调试对应的是 0x1f6bb000 */
        /* 2： add  x2, x2, #0x0 ==> 0x0 就是 你要拿的那个符号在这个4K页里面存放时先对页起始地址的偏移，这里偏移就是0 ==> 用这个方法来实现将某个全局变量的运行时的地址加载到寄存器中去  */
        /* tmp2 ==> 这个寄存器里面最终存放的就是 ptbl 这个符号的 运行时的物理地址  */
        adr_l \tmp2, \ptbl
        /* tmp3寄存器里面存放的就是该页表的某个entry的内容了 ==> 将这些内容写到该级页表对应的entry的内存中去 */
        /* tmp1 就是这级页表的entry的索引值idx, 也叫做slot,因为一个entry是8个字节，64位，所以这里左了3位，也就是 x8，就得到了idx对应的这个entry的偏移地址了 */
        str   \tmp3, [\tmp2, \tmp1, lsl #3]
.endm

/*
 * Macro to create a mapping entry in \tbl to \phys. Only mapping in 3rd
 * level table (i.e page granularity) is supported.
 *
 * ptbl:     table symbol where the entry will be created
 * virt:    virtual address
 * phys:    physical address (should be page aligned)
 * tmp1:    scratch register
 * tmp2:    scratch register
 * tmp3:    scratch register
 * type:    mapping type. If not specified it will be normal memory (PT_MEM_L3)
 *
 * Preserves \virt, \phys
 * Clobbers \tmp1, \tmp2, \tmp3
 *
 * Note that all parameters using registers should be distinct.
 */
.macro create_mapping_entry, ptbl, virt, phys, tmp1, tmp2, tmp3, type=PT_MEM_L3
        /* #define THIRD_MASK  ==> 0xfffffffffffff000 */
        /* and ==> 与操作 ==> phys & 0xfffffffffffff000  ==> 就是4K对齐后的地址 存放在tmp3 中 */
        and   \tmp3, \phys, #THIRD_MASK     /* \tmp3 := PAGE_ALIGNED(phys) */

        /* lvl=0 ===> ubfx  \slot, \virt, #39, #9  ==> slot = (virt >> 39) & ((1 << 9) - 1) */
        /* lvl=1 ===> ubfx  \slot, \virt, #30, #9  ==> slot = (virt >> 30) & ((1 << 9) - 1) */
        /* lvl=2 ===> ubfx  \slot, \virt, #21, #9  ==> slot = (virt >> 21) & ((1 << 9) - 1) */
        /* lvl=3 ===> ubfx  \slot, \virt, #12, #9  ==> slot = (virt >> 12) & ((1 << 9) - 1) */
        /* .macro get_table_slot, slot, virt, lvl */
        /* tmp1 = (virt >> 12) & 0x1ff ==> 取 4K以上的 9bit */
        get_table_slot \tmp1, \virt, 3      /* \tmp1 := slot in \tlb */

        /* 下面就是做配置 页表的entry的填充内存 */
        /* #define PT_MEM_L3 0xf7f ==> nG=1 AF=1 SH=11 AP=01 NS=1 ATTR=111 T=1 P=1  */
        /* 填充内容 = 属性信息 + phys的4K对齐后的物理地址 */
        mov   \tmp2, #\type                 /* \tmp2 := right for section PT */
        orr   \tmp2, \tmp2, \tmp3           /*          + PAGE_ALIGNED(phys) */
        /* 下面的解析是直接拷贝了上面的，因为都是adr_l伪指令 */
        /* qemu 看真实的指令，发现下面指令最终用了两条指令来实现adr_l想要的功能 */
        /* 1： adrp x2, ptbl ==> 得到 ptbl 运行时 进行4K页对齐后的物理地址 ==> 比如这里调试对应的是 0x1f6bb000 */
        /* 2： add  x2, x2, #0x0 ==> 0x0 就是 你要拿的那个符号在这个4K页里面存放时先对页起始地址的偏移，这里偏移就是0 ==> 用这个方法来实现将某个全局变量的运行时的地址加载到寄存器中去  */
        /* tmp3 ==> 这个寄存器里面最终存放的就是 ptbl 这个符号的 运行时的物理地址  */
        adr_l \tmp3, \ptbl
        /* 将entry 的填充内容写到 对应的 entry 里面去， tmp1为 entry 的 idx, 一个entry 8个字节  */
        /* 所以这里起始就是配置了第3级页表，这个页表里面的entry 保护了一个 物理页的起始物理地址，也就是指向了这个物理页  */
        str   \tmp2, [\tmp3, \tmp1, lsl #3]
.endm

/*
 * Rebuild the boot pagetable's first-level entries. The structure
 * is described in mm.c.
 *
 * After the CPU enables paging it will add the fixmap mapping
 * to these page tables, however this may clash with the 1:1
 * mapping. So each CPU must rebuild the page tables here with
 * the 1:1 in place.
 *
 * Inputs:
 *   x19: paddr(start)
 *   x20: phys offset
 *
 * Clobbers x0 - x4
 */
create_page_tables:
        /* Prepare the page-tables for mapping Xen */
        /* XEN_VIRT_START就是XEN代码段的起始链接地址 */
        /* 下面是一条伪指令，qemu看实际的汇编指令，发现是用一条 ldr x0,0x1f600840 指令替换的，当然这条指令的 0x1f600840 是gdb加工后的结果 */
        /* ldr x0,0x1f600840 ==> 真实的ldr指令就是加载指定的地址上的内存数据到目的寄存器 ==> 这里加载 0x1f600840 上的数据 到 x0  */
        /* x0 = 0x20000200000  */
        /* p /x $x0 ==> x0 = 0x20000200000 */
        /* 
            其实这里也就是满足了下面的伪指令的功能，下面的伪指令，ldr x0,=XEN_VIRT_START, 有个=号，就表示要加载这个符号的编译链接时的链接地址，
            链接地址在这里也就是虚拟地址了，加载这个链接地址到x0，用做下面的虚拟地址 进行映射
        */
        ldr x0, =XEN_VIRT_START 

        /* x0 为要映射的虚拟地址  */
        /* 0 ==> 第0级页表 */
        /* x1, x2, x3 ==> 为过程中要用到的中间寄存器 */
        /* 
                create_table_entry
                从下面函数的实现分析来看 ==> 为映射virt这个虚拟地址，要逐级填充各级页表的对应的entry 
                ==> 那么这里就是通过lvl来指定要填充的是第几级页表，ptbl指向这个要被填充的页表基地址，
                ==> 然后通过虚拟地址virt来索引该级页表的对应的entry
                ==> 这个entry中要填充 下一级页表的物理基地址(tbl) 以及相关的页表属性 
        */
        /* 为映射虚拟地址x0(XEN_VIRT_START), 这里先填充第0级页表(boot_pgtable)的 对应的entry ==> 填充内容包含下一级页表的物理基地址(boot_first) + 一些基本属性  */
        create_table_entry boot_pgtable, boot_first, x0, 0, x1, x2, x3   
        /* 为映射虚拟地址x0(XEN_VIRT_START), 这里先填充第1级页表(boot_first)的 对应的entry ==> 填充内容包含下一级页表的物理基地址(boot_second) + 一些基本属性  */
        create_table_entry boot_first, boot_second,  x0, 1, x1, x2, x3
        /* 为映射虚拟地址x0(XEN_VIRT_START), 这里先填充第2级页表(boot_second)的 对应的entry ==> 填充内容包含下一级页表的物理基地址(boot_third) + 一些基本属性  */
        create_table_entry boot_second, boot_third,  x0, 2, x1, x2, x3

        /* 9 + 9 + 9 + 12 ==> 4级页表 ==> 最后一级在下面填写 */
        /* 下面的图 在create_table_entry宏中也有画与有更详细的解析 */
/* 
ttbr0_el2 ==> |level0_entry0(4K or 512_entry)    ==> |level1_entry0(4K or 512_entry) ==>  |level2_entry0(4K or 512_entry)  ==>  |level3_entry0(4K or 512_entry) ==> include start paddr of 4K page 
              |                                      |                                    |                                     | ...
              |                                      |                                    |                                     |level3_entry511(4K or 512_entry) ==> include start paddr of 4K page 
              |                                      |                                    | ...
              |                                      |                                    |level2_entry512(4K or 512_entry)
              |                                      |    ....
              |                                      |level1_entry511(4K or 512_entry) ==> ...
              |           ....
              |level0_entry511(4K or 512_entry)  ==> |level1_entry0(4K or 512_entry) ==>  ...
                                                     |    ....
                                                     |level1_entry511(4K or 512_entry) ==>  ...
*/


        /* Map Xen */
        /* 通过反汇编看，adr_l 也是用 adrp + add的方式来实现的 */
        /* adrp x4,xxxx */
        /* add  x4,x4,#0x0 ==> 最终x4 = 0x1f6c1000 ==> boot_third 运行时的物理地址就是 0x1f6c1000 ==> 也就是找到了第三级页表的起始物理地址  */
        adr_l x4, boot_third

        /* Logical Shift Right ==> THIRD_SHIFT 是 12 */
        /* x19是调用这个函数之前，就设置好值了 ==>  adr  x19, start ， $x19=0x1f600000 ==> x19 := paddr (start)  */
        /* start符号的运行时的物理地址 存放在 x19 中 */
        lsr   x2, x19, #THIRD_SHIFT  /* Base address for 4K mapping ==> x2 = x19 >> 12 = 0x1f600 */
        /* Logical Shift Left ==> x2 = x2 << 12 = 0x1f600000  */
        lsl   x2, x2, #THIRD_SHIFT 
        /* #define PT_MEM_L3 0xf7f ==> nG=1 AF=1 SH=11 AP=01 NS=1 ATTR=111 T=1 P=1  ==> 属性值 */
        mov   x3, #PT_MEM_L3         /* x2 := Section map */
        /*  ORR <Xd>, <Xn>, <Xm> ==>  Xd = Xn | Xm;  */
        /* x2 = x2 | x3 ==>  0x1f600000 | 0xf7f = 0x1f600f7f ==> 这个就是页表entry里面要填充的内容 */
        /* 也就是 XEN_VIRT_START 这个虚拟地址 经过这里配置好的页表后，最终映射到了物理地址 paddr(start),也就是0x1f600000这个物理地址上 */
        orr   x2, x2, x3

        /* ... map of vaddr(start) in boot_third */
        /* XZR 64 bits 31 Zero register */
        mov   x1, xzr
        /* 将上面填充好的表项的内容(x2) 填充到 第三级页表的第0个entry 中去（x1是entry的偏移地址） */
1:      str   x2, [x4, x1]           /* Map vaddr(start) */
        /* #define PAGE_SIZE   (_AC(1,L) << PAGE_SHIFT) */
        add   x2, x2, #PAGE_SIZE     /* Next page */
        /* x1 + 8 ==> 就是 第三级页表的 下一个entry的偏移地址 ==> 因为一个entry 8个字节  */
        add   x1, x1, #8             /* Next slot */
        /*  XEN_PT_LPAE_ENTRIES ==> 是  (1U << 9 ) ==> 512 */
        /* cmp x1,#(512<<3) ==>  cmp x1,#4096 */
        /* CMP <Xn|SP>, #<imm>{, <shift>} ==> is equivalent to ==> SUBS XZR, <Xn|SP>, #<imm>{, <shift>} */
        /* 下面的代码的意思就是，x1 < 4096 就继续填充对应的entry，这里要做的是将这整页4K的所有entry都填充为相同的内容，也就是指向了同一页 */
        cmp   x1, #(XEN_PT_LPAE_ENTRIES<<3) /* 512 entries per page */
        /* 512个entry都填充了后，就填充完了，继续往下走 */
        /*
                (gdb) x /10x 0x1f6c1000  ==> boot_third 运行时的物理地址就是0x1f6c1000  
                0x1f6c1000:	0x1f600f7f	0x00000000	0x1f601f7f	0x00000000
                0x1f6c1010:	0x1f602f7f	0x00000000	0x1f603f7f	0x00000000
                0x1f6c1020:	0x1f604f7f	0x00000000
        */
        b.lt  1b

        /*
         * If Xen is loaded at exactly XEN_VIRT_START then we don't
         * need an additional 1:1 mapping, the virtual mapping will
         * suffice.
         */
        /* XEN_VIRT_START就是XEN代码段的起始链接地址 */
        /* 下面是一条伪指令，qemu看实际的汇编指令，发现是用一条 ldr x0,0x1f600840 指令替换的，当然这条指令的 0x1f600840 是gdb加工后的结果 */
        /* ldr x0,0x1f600840 ==> 真实的ldr指令就是加载指定的地址上的内存数据到目的寄存器 ==> 这里加载 0x1f600840 上的数据 到 x0  */
        /* x0 = 0x20000200000  */
        /* p /x $x0 ==> x0 = 0x20000200000 */
        /* 
            其实这里也就是满足了下面的伪指令的功能，下面的伪指令，ldr x0,=XEN_VIRT_START, 有个=号，就表示要加载这个符号的编译链接时的链接地址，
            链接地址在这里也就是虚拟地址了，加载这个链接地址到x0，用做下面的虚拟地址 进行映射
        */
        ldr   x0, =XEN_VIRT_START
        /* x19 = 0x1f600000; x0 = 0x20000200000 */
        cmp   x19, x0
        /* 跳到下面的 get_table_slot 处执行 */
        bne   1f
        ret
1:
        /*
         * Setup the 1:1 mapping so we can turn the MMU on. Note that
         * only the first page of Xen will be part of the 1:1 mapping.
         */

        /*
         * Find the zeroeth slot used. If the slot is not
         * XEN_ZEROETH_SLOT, then the 1:1 mapping will use its own set of
         * page-tables from the first level.
         */
        /* .macro get_table_slot, slot, virt, lvl */
        /* lvl=0 ===> ubfx  \slot, \virt, #39, #9  ==> slot = (virt >> 39) & ((1 << 9) - 1) */
        /* lvl=1 ===> ubfx  \slot, \virt, #30, #9  ==> slot = (virt >> 30) & ((1 << 9) - 1) */
        /* lvl=2 ===> ubfx  \slot, \virt, #21, #9  ==> slot = (virt >> 21) & ((1 << 9) - 1) */
        /* lvl=3 ===> ubfx  \slot, \virt, #12, #9  ==> slot = (virt >> 12) & ((1 << 9) - 1) */
        /* 这里的lvl为0 ==> x0 = (x19 >> 39) & ((1 << 9) - 1) */
        /* 这里的lvl为0 ==> x0 = (0x1f600000 >> 39) & 0x1ff */
        /* x0=0  */
        get_table_slot x0, x19, 0       /* x0 := zeroeth slot */
        /*  XEN_ZEROETH_SLOT = 4 */
        cmp   x0, #XEN_ZEROETH_SLOT
        beq   1f
        /* 走到这里了，上面代码不跳转到 1f去 */
        /* x19=0x1f600000 */
        /* create_table_entry 这个函数已经注释过了 */
        /* 这里也就是要将 0x1f600000 单做一个虚拟地址来进行映射了，估计就是为了1:1映射 */
        create_table_entry boot_pgtable, boot_first_id, x19, 0, x0, x1, x2
        /* 直接跳到了 下面的 link_from_first_id 这个标号处开始执行，会逐级映射好页表 */
        b     link_from_first_id

1:
        /*
         * Find the first slot used. If the slot is not XEN_FIRST_SLOT,
         * then the 1:1 mapping will use its own set of page-tables from
         * the second level.
         */
        get_table_slot x0, x19, 1      /* x0 := first slot */
        cmp   x0, #XEN_FIRST_SLOT
        beq   1f
        create_table_entry boot_first, boot_second_id, x19, 1, x0, x1, x2
        b     link_from_second_id

1:
        /*
         * Find the second slot used. If the slot is XEN_SECOND_SLOT, then the
         * 1:1 mapping will use its own set of page-tables from the
         * third level. For slot XEN_SECOND_SLOT, Xen is not yet able to handle
         * it.
         */
        get_table_slot x0, x19, 2     /* x0 := second slot */
        cmp   x0, #XEN_SECOND_SLOT
        beq   virtphys_clash
        create_table_entry boot_second, boot_third_id, x19, 2, x0, x1, x2
        b     link_from_third_id

link_from_first_id:
        create_table_entry boot_first_id, boot_second_id, x19, 1, x0, x1, x2
link_from_second_id:
        create_table_entry boot_second_id, boot_third_id, x19, 2, x0, x1, x2
link_from_third_id:
        create_mapping_entry boot_third_id, x19, x19, x0, x1, x2
        ret

virtphys_clash:
        /* Identity map clashes with boot_third, which we cannot handle yet */
        PRINT("- Unable to build boot page tables - virt and phys addresses clash. -\r\n")
        b     fail
ENDPROC(create_page_tables)

/*
 * Turn on the Data Cache and the MMU. The function will return on the 1:1
 * mapping. In other word, the caller is responsible to switch to the runtime
 * mapping.
 *
 * Inputs:
 *   x0 : Physical address of the page tables.
 *
 * Clobbers x0 - x4
 */
enable_mmu:
        mov   x4, x0
        PRINT("- Turning on paging -\r\n")

        /*
         * The state of the TLBs is unknown before turning on the MMU.
         * Flush them to avoid stale one.
         */
        tlbi  alle2                  /* Flush hypervisor TLBs */
        dsb   nsh

        /* Write Xen's PT's paddr into TTBR0_EL2 */
        msr   TTBR0_EL2, x4
        isb

        mrs   x0, SCTLR_EL2
        orr   x0, x0, #SCTLR_Axx_ELx_M  /* Enable MMU */
        orr   x0, x0, #SCTLR_Axx_ELx_C  /* Enable D-cache */
        dsb   sy                     /* Flush PTE writes and finish reads */
        msr   SCTLR_EL2, x0          /* now paging is enabled */
        isb                          /* Now, flush the icache */
        ret
ENDPROC(enable_mmu)

/*
 * Remove the 1:1 map from the page-tables. It is not easy to keep track
 * where the 1:1 map was mapped, so we will look for the top-level entry
 * exclusive to the 1:1 map and remove it.
 *
 * Inputs:
 *   x19: paddr(start)
 *
 * Clobbers x0 - x1
 */
remove_identity_mapping:
        /*
         * Find the zeroeth slot used. Remove the entry from zeroeth
         * table if the slot is not XEN_ZEROETH_SLOT.
         */
        get_table_slot x1, x19, 0       /* x1 := zeroeth slot */
        cmp   x1, #XEN_ZEROETH_SLOT
        beq   1f
        /* It is not in slot XEN_ZEROETH_SLOT, remove the entry. */
        ldr   x0, =boot_pgtable         /* x0 := root table */
        str   xzr, [x0, x1, lsl #3]
        b     identity_mapping_removed

1:
        /*
         * Find the first slot used. Remove the entry for the first
         * table if the slot is not XEN_FIRST_SLOT.
         */
        get_table_slot x1, x19, 1       /* x1 := first slot */
        cmp   x1, #XEN_FIRST_SLOT
        beq   1f
        /* It is not in slot XEN_FIRST_SLOT, remove the entry. */
        ldr   x0, =boot_first           /* x0 := first table */
        str   xzr, [x0, x1, lsl #3]
        b     identity_mapping_removed

1:
        /*
         * Find the second slot used. Remove the entry for the first
         * table if the slot is not XEN_SECOND_SLOT.
         */
        get_table_slot x1, x19, 2       /* x1 := second slot */
        cmp   x1, #XEN_SECOND_SLOT
        beq   identity_mapping_removed
        /* It is not in slot 1, remove the entry */
        ldr   x0, =boot_second          /* x0 := second table */
        str   xzr, [x0, x1, lsl #3]

identity_mapping_removed:
        /* See asm/arm64/flushtlb.h for the explanation of the sequence. */
        dsb   nshst
        tlbi  alle2
        dsb   nsh
        isb

        ret
ENDPROC(remove_identity_mapping)

/*
 * Map the UART in the fixmap (when earlyprintk is used) and hook the
 * fixmap table in the page tables.
 *
 * The fixmap cannot be mapped in create_page_tables because it may
 * clash with the 1:1 mapping.
 *
 * Inputs:
 *   x20: Physical offset
 *   x23: Early UART base physical address
 *
 * Clobbers x0 - x3
 */
setup_fixmap:
#ifdef CONFIG_EARLY_PRINTK
        /* Add UART to the fixmap table */
        ldr   x0, =EARLY_UART_VIRTUAL_ADDRESS
        create_mapping_entry xen_fixmap, x0, x23, x1, x2, x3, type=PT_DEV_L3
#endif
        /* Map fixmap into boot_second */
        ldr   x0, =FIXMAP_ADDR(0)
        create_table_entry boot_second, xen_fixmap, x0, 2, x1, x2, x3
        /* Ensure any page table updates made above have occurred. */
        dsb   nshst

        ret
ENDPROC(setup_fixmap)

/*
 * Setup the initial stack and jump to the C world
 *
 * Inputs:
 *   x0 : Argument 0 of the C function to call
 *   x1 : Argument 1 of the C function to call
 *   x2 : C entry point
 *
 * Clobbers x3
 */
launch:
        ldr   x3, =init_data
        add   x3, x3, #INITINFO_stack /* Find the boot-time stack */
        ldr   x3, [x3]
        add   x3, x3, #STACK_SIZE     /* (which grows down from the top). */
        sub   x3, x3, #CPUINFO_sizeof /* Make room for CPU save record */
        mov   sp, x3

        /* Jump to C world */
        br    x2
ENDPROC(launch)

/* Fail-stop */
fail:   PRINT("- Boot failed -\r\n")
1:      wfe
        b     1b
ENDPROC(fail)

/*
 * Switch TTBR
 *
 * x0    ttbr
 */
ENTRY(switch_ttbr_id)
        /* 1) Ensure any previous read/write have completed */
        dsb    ish
        isb

        /* 2) Turn off MMU */
        mrs    x1, SCTLR_EL2
        bic    x1, x1, #SCTLR_Axx_ELx_M
        msr    SCTLR_EL2, x1
        isb

        /*
         * 3) Flush the TLBs.
         * See asm/arm64/flushtlb.h for the explanation of the sequence.
         */
        dsb   nshst
        tlbi  alle2
        dsb   nsh
        isb

        /* 4) Update the TTBR */
        msr   TTBR0_EL2, x0
        isb

        /*
         * 5) Flush I-cache
         * This should not be necessary but it is kept for safety.
         */
        ic     iallu
        isb

        /* 6) Turn on the MMU */
        mrs   x1, SCTLR_EL2
        orr   x1, x1, #SCTLR_Axx_ELx_M  /* Enable MMU */
        msr   SCTLR_EL2, x1
        isb

        ret
ENDPROC(switch_ttbr_id)

#ifdef CONFIG_EARLY_PRINTK
/*
 * Initialize the UART. Should only be called on the boot CPU.
 *
 * Output:
 *  x23: Early UART base physical address
 *
 * Clobbers x0 - x1
 */
init_uart:
        ldr   x23, =CONFIG_EARLY_UART_BASE_ADDRESS /* =CONFIG_EARLY_UART_BASE_ADDRESS ==> 0x1f6007f8 */
#ifdef CONFIG_EARLY_UART_INIT  /* 这个宏没有定义 */
        early_uart_init x23, 0
#endif
        PRINT("- UART enabled -\r\n")
        ret
ENDPROC(init_uart)

/* Print early debug messages.
 * x0: Nul-terminated string to print.
 * x23: Early UART base address
 * Clobbers x0-x1 */
puts:
        early_uart_ready x23, 1
        ldrb  w1, [x0], #1           /* Load next char */
        cbz   w1, 1f                 /* Exit on nul */
        early_uart_transmit x23, w1
        b     puts
1:
        ret
ENDPROC(puts)

/*
 * Print a 64-bit number in hex.
 * x0: Number to print.
 * x23: Early UART base address
 * Clobbers x0-x3
 */
putn:
        adr   x1, hex
        mov   x3, #16
1:
        early_uart_ready x23, 2
        and   x2, x0, #(0xf<<60)     /* Mask off the top nybble */
        lsr   x2, x2, #60
        ldrb  w2, [x1, x2]           /* Convert to a char */
        early_uart_transmit x23, w2
        lsl   x0, x0, #4             /* Roll it through one nybble at a time */
        subs  x3, x3, #1
        b.ne  1b
        ret
ENDPROC(putn)

hex:    .ascii "0123456789abcdef"
        .align 2

#else  /* CONFIG_EARLY_PRINTK */

ENTRY(early_puts)
init_uart:
puts:
putn:   ret

#endif /* !CONFIG_EARLY_PRINTK */

/* This provides a C-API version of __lookup_processor_type
 * TODO: For now, the implementation return NULL every time
 */
ENTRY(lookup_processor_type)
        mov  x0, #0
        ret
/*
 *  Function to transition from EFI loader in C, to Xen entry point.
 *  void noreturn efi_xen_start(void *fdt_ptr, uint32_t fdt_size);
 */
ENTRY(efi_xen_start)
        /*
         * Preserve x0 (fdt pointer) across call to __flush_dcache_area,
         * restore for entry into Xen.
         */
        mov   x20, x0

        /* flush dcache covering the FDT updated by EFI boot code */
        bl    __flush_dcache_area

        /*
         * Flush dcache covering current runtime addresses
         * of xen text/data. Then flush all of icache.
         */
        adr_l x1, _start
        mov   x0, x1
        adr_l x2, _end
        sub   x1, x2, x1

        bl    __flush_dcache_area
        ic    ialluis
        tlbi  alle2

        /*
         * Turn off cache and MMU as Xen expects. EFI enables them, but also
         * mandates a 1:1 (unity) VA->PA mapping, so we can turn off the
         * MMU while executing EFI code before entering Xen.
         * The EFI loader calls this to start Xen.
         */

        /* Turn off Dcache and MMU */
        mrs   x0, sctlr_el2
        bic   x0, x0, #1 << 0        /* clear SCTLR.M */
        bic   x0, x0, #1 << 2        /* clear SCTLR.C */
        msr   sctlr_el2, x0
        isb

        /* Jump to Xen entry point */
        mov   x0, x20
        mov   x1, xzr
        mov   x2, xzr
        mov   x3, xzr
        /*
         * The EFI stub and Xen may share some information living in
         * BSS. Don't zero BSS to avoid loosing them.
         *
         * Note that the EFI firmware has already zeroed BSS for us
         * before jump into the stub.
         */
        mov   x26, #1               /* x26 := skip_zero_bss */

        b     real_start_efi
ENDPROC(efi_xen_start)

/*
 * Local variables:
 * mode: ASM
 * indent-tabs-mode: nil
 * End:
 */
