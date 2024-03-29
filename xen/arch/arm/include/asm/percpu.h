#ifndef __ARM_PERCPU_H__
#define __ARM_PERCPU_H__

#ifndef __ASSEMBLY__

#include <xen/types.h>
#include <asm/sysregs.h>

extern char __per_cpu_start[], __per_cpu_data_end[];
extern unsigned long __per_cpu_offset[NR_CPUS];
void percpu_init_areas(void);

#define per_cpu(var, cpu)  \
    (*RELOC_HIDE(&per_cpu__##var, __per_cpu_offset[cpu]))

/* #define RELOC_HIDE(ptr, off)  ==>  */
/* 每个CPU的TPIDR_EL2寄存器中，存放的就是 每个CPU自己的per_cpu变量的偏移值 */
/* 所以只要指定per_cpu变量的起始地址，然后每个CPU就能知道属于自己的那个percpu变量的地址(起始地址 + offset) */
/* 参考 ==> 0:percpu变量的实现原理  */
#define this_cpu(var) \
    (*RELOC_HIDE(&per_cpu__##var, READ_SYSREG(TPIDR_EL2)))

#define per_cpu_ptr(var, cpu)  \
    (*RELOC_HIDE(var, __per_cpu_offset[cpu]))
#define this_cpu_ptr(var) \
    (*RELOC_HIDE(var, READ_SYSREG(TPIDR_EL2)))

#endif

#endif /* __ARM_PERCPU_H__ */
/*
 * Local variables:
 * mode: C
 * c-file-style: "BSD"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 */
