#include <xen/bitops.h>
#include <xen/init.h>
#include <xen/irq.h>
#include <xen/pmap.h>

#include <asm/pmap.h>
#include <asm/fixmap.h>

/*
 * Simple mapping infrastructure to map / unmap pages in fixed map.
 * This is used to set the page table before the map domain page infrastructure
 * is initialized.
 *
 * This structure is not protected by any locks, so it must not be used after
 * smp bring-up.
 */

/* Bitmap to track which slot is used */
static __initdata DECLARE_BITMAP(inuse, NUM_FIX_PMAP);

void *__init pmap_map(mfn_t mfn) // 将mfn 映射到 Fixmap虚拟地址空间
{
    unsigned int idx;
    unsigned int slot;

    ASSERT(system_state < SYS_STATE_smp_boot);
    ASSERT(!in_irq());

    idx = find_first_zero_bit(inuse, NUM_FIX_PMAP);
    if ( idx == NUM_FIX_PMAP )
        panic("Out of PMAP slots\n");

    __set_bit(idx, inuse);

    slot = idx + FIXMAP_PMAP_BEGIN;  // #define FIXMAP_PMAP_BEGIN  66(0x42)  /* Start of PMAP */ ==> slot 这里固定从0x42开始
    ASSERT(slot >= FIXMAP_PMAP_BEGIN && slot <= FIXMAP_PMAP_END);

    /*
     * We cannot use set_fixmap() here. We use PMAP when the domain map
     * page infrastructure is not yet initialized, so map_pages_to_xen() called
     * by set_fixmap() needs to map pages on demand, which then calls pmap()
     * again, resulting in a loop. Modify the PTEs directly instead. The same
     * is true for pmap_unmap().
     */
    arch_pmap_map(slot, mfn); // 将 物理地址页框号mfn【待映射的物理i地址】映射到slot 对应的虚拟地址空间上来

    return fix_to_virt(slot); // slot号【也就是物理地址】 转换为虚拟地址 【物理地址存放在xen_fixmap[slot]这个页表中，xen_fixmap[x]就是pte了】
                              // xen_fixmap[0]   ==> 0x20000400000 
                              // xen_fixmap[1]   ==> 0x20000401000 
                              // xen_fixmap[2]   ==> 0x20000402000 
                              // ...
                              // xen_fixmap[0x42]   ==> 0x20000442000 
                              // xen_fixmap[0x43]   ==> 0x20000443000 
                              // ...
                              // xen_fixmap[511] ==> 0x200005ff000  ==> 512个entry * 4K = 2M 
                              // 4M-6M ==> Fixmap: special-purpose 4K mapping slots 0x20000400000 -- 0x200005fffff 
}

void __init pmap_unmap(const void *p)
{
    unsigned int idx;
    unsigned int slot = virt_to_fix((unsigned long)p);

    ASSERT(system_state < SYS_STATE_smp_boot);
    ASSERT(slot >= FIXMAP_PMAP_BEGIN && slot <= FIXMAP_PMAP_END);
    ASSERT(!in_irq());

    idx = slot - FIXMAP_PMAP_BEGIN;

    __clear_bit(idx, inuse);
    arch_pmap_unmap(slot);
}

/*
 * Local variables:
 * mode: C
 * c-file-style: "BSD"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 */
