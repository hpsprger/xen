#ifndef __ASM_PMAP_H__
#define __ASM_PMAP_H__

#include <xen/mm.h>

#include <asm/fixmap.h>

static inline void arch_pmap_map(unsigned int slot, mfn_t mfn)
{
    lpae_t *entry = &xen_fixmap[slot]; // xen_fixmap[xx] ==> 已经挂到了 boot_second级 页表的某个entry下，所以 xen_fixmap[xx] 各个entry对应的
                                       // 虚拟地址空间是已经确定了的
                                       // slot号【也就是物理地址】 转换为虚拟地址 【物理地址存放在xen_fixmap[slot]这个页表中，xen_fixmap[x]就是pte了】
                                       // xen_fixmap[0]   ==> 0x20000400000 
                                       // xen_fixmap[1]   ==> 0x20000401000 
                                       // xen_fixmap[2]   ==> 0x20000402000 
                                       // ...
                                       // xen_fixmap[0x42]   ==> 0x20000442000 
                                       // xen_fixmap[0x43]   ==> 0x20000443000 
                                       // ...
                                       // xen_fixmap[511] ==> 0x200005ff000  ==> 512个entry * 4K = 2M 
                                       // 4M-6M ==> Fixmap: special-purpose 4K mapping slots 0x20000400000 -- 0x200005fffff 
    lpae_t pte;

    ASSERT(!lpae_is_valid(*entry));

    pte = mfn_to_xen_entry(mfn, PAGE_HYPERVISOR_RW); // 构造一个pte entry 的 各个位的信息 ， 这个pte entry 里面包含了下一级页表的 4K物理页的物理地址页框号mfn与相关的属性信息
    pte.pt.table = 1;
    write_pte(entry, pte);  // 把上面构造好的pte entry 数据 填写到  xen_fixmap[slot] 这个entry上，从而实现 物理地址 与 虚拟地址 的映射 
}

static inline void arch_pmap_unmap(unsigned int slot)
{
    lpae_t pte = {};

    write_pte(&xen_fixmap[slot], pte);

    flush_xen_tlb_range_va_local(FIXMAP_ADDR(slot), PAGE_SIZE);
}

#endif /* __ASM_PMAP_H__ */
