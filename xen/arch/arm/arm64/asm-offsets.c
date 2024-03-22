/*
 * Generate definitions needed by assembly language modules.
 * This code generates raw asm output which is post-processed
 * to extract and format the required data.
 */
#define COMPILE_OFFSETS

#include <xen/types.h>
#include <xen/sched.h>
#include <xen/bitops.h>
#include <public/xen.h>
#include <asm/current.h>
#include <asm/setup.h>
#include <asm/smccc.h>

#define DEFINE(_sym, _val)                                                 \
    asm volatile ("\n.ascii\"==>#define " #_sym " %0 /* " #_val " */<==\"" \
                  : : "i" (_val) )
#define BLANK()                                                            \
    asm volatile ( "\n.ascii\"==><==\"" : : )
#define OFFSET(_sym, _str, _mem)                                           \
    DEFINE(_sym, offsetof(_str, _mem));

void __dummy__(void)
{
   OFFSET(UREGS_X0, struct cpu_user_regs, x0);
   OFFSET(UREGS_X1, struct cpu_user_regs, x1);
   OFFSET(UREGS_LR, struct cpu_user_regs, lr);

   OFFSET(UREGS_SP, struct cpu_user_regs, sp);
   OFFSET(UREGS_PC, struct cpu_user_regs, pc);
   OFFSET(UREGS_CPSR, struct cpu_user_regs, cpsr);
   OFFSET(UREGS_ESR_el2, struct cpu_user_regs, hsr);

   OFFSET(UREGS_SPSR_el1, struct cpu_user_regs, spsr_el1);

   OFFSET(UREGS_SPSR_fiq, struct cpu_user_regs, spsr_fiq);
   OFFSET(UREGS_SPSR_irq, struct cpu_user_regs, spsr_irq);
   OFFSET(UREGS_SPSR_und, struct cpu_user_regs, spsr_und);
   OFFSET(UREGS_SPSR_abt, struct cpu_user_regs, spsr_abt);

   OFFSET(UREGS_SP_el0, struct cpu_user_regs, sp_el0);
   OFFSET(UREGS_SP_el1, struct cpu_user_regs, sp_el1);
   OFFSET(UREGS_ELR_el1, struct cpu_user_regs, elr_el1);

   OFFSET(UREGS_kernel_sizeof, struct cpu_user_regs, spsr_el1);
   BLANK();

   DEFINE(CPUINFO_sizeof, sizeof(struct cpu_info));
   OFFSET(CPUINFO_flags, struct cpu_info, flags);

   OFFSET(VCPU_arch_saved_context, struct vcpu, arch.saved_context);

   BLANK();
/* 
#define offsetof(a,b) __builtin_offsetof(a,b)



   #define OFFSET(_sym, _str, _mem)                                                      
   OFFSET(INITINFO_stack, struct init_info, stack) ==>  DEFINE(_sym, offsetof(_str, _mem)); 
                                                        DEFINE(INITINFO_stack, offsetof(struct init_info, stack))
                                                        DEFINE(INITINFO_stack, __builtin_offsetof(struct init_info, stack)）

//#define DEFINE(_sym, _val)                                                 \
//    asm volatile ("\n.ascii\"==>#define " #_sym " %0 /* " #_val " */<==\"" \
//                  : : "i" (_val) )

__builtin_offsetof 是一个 GCC 编译器内建函数，用于计算结构体（struct）或联合体（union）中某个成员相对于其所在结构体或联合体开始地址的偏移量。


*/

#define DEFINE(_sym, _val)                                                 \
    asm volatile ("\n.ascii\"==>#define " #_sym " %0 /* " #_val " */<==\"" \
                  : : "i" (_val) )


   OFFSET(INITINFO_stack, struct init_info, stack);

   BLANK();
   OFFSET(SMCCC_RES_a0, struct arm_smccc_res, a0);
   OFFSET(SMCCC_RES_a2, struct arm_smccc_res, a2);
}

/*
 * Local variables:
 * mode: C
 * c-file-style: "BSD"
 * c-basic-offset: 4
 * indent-tabs-mode: nil
 * End:
 */
