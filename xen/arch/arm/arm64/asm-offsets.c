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

#if 0

//可以拆分为下面几个部分
//" .ascii"==>#define "  ==> .ascii 是一个汇编指令，用于在输出中插入一个 ASCII 字符串
// #INITINFO_stack
//  " %0 /* " 
//   #xxx

==> 生成的字符串形式大致为 ==>#define _sym 值 /* 值 */<==，其中 _sym 和 值 分别是宏名称和它的值。

下面是该宏定义的分解：
#define DEFINE(_sym, _val): 定义了一个名为 DEFINE 的宏，它接受两个参数：_sym 和 _val。

asm volatile (...): 这是一个 GCC 内联汇编语句的开始。volatile 关键字告诉编译器不要优化或重新排序这个汇编代码块。

"\n.ascii\"==>#define " #_sym " %0 /* " #_val " */<==\"\n": 这是内联汇编的模板字符串。

#_sym 和 #_val 是宏参数的字符串化操作。这意味着它们会被替换为它们各自的字符串字面量。

%0 是一个占位符，它会被后面的 :"i" (_val) 替换为 _val 的值。

.ascii 是一个汇编指令，用于在输出中插入一个 ASCII 字符串。

生成的字符串形式大致为 ==>#define _sym 值 /* 值 */<==，其中 _sym 和 值 分别是宏名称和它的值。

: : "i" (_val): 这是内联汇编的输入部分。它告诉编译器将 _val 作为立即数（integer constant）传递给汇编代码。在这里，它实际上并不传递给汇编代码任何输入，而是作为 %0 的替换值。
#endif

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
*/

   OFFSET(INITINFO_stack, struct init_info, stack); //也是用汇编指令 .ascii 定义了一个宏，#define INITINFO_stack offset(struct init_info中stack的偏移量)

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
