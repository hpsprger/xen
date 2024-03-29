#ifndef __LINUX_COMPILER_H
#define __LINUX_COMPILER_H

#if !defined(__GNUC__) || (__GNUC__ < 4)
#error Sorry, your compiler is too old/not recognized.
#elif CONFIG_CC_IS_GCC
# if defined(CONFIG_ARM_32) && CONFIG_GCC_VERSION < 40900
#  error Sorry, your version of GCC is too old - please use 4.9 or newer.
# elif defined(CONFIG_ARM_64) && CONFIG_GCC_VERSION < 50100
/*
 * https://gcc.gnu.org/bugzilla/show_bug.cgi?id=63293
 * https://lore.kernel.org/r/20210107111841.GN1551@shell.armlinux.org.uk
 */
#  error Sorry, your version of GCC is too old - please use 5.1 or newer.
# endif
#endif

#define barrier()     __asm__ __volatile__("": : :"memory")

#define likely(x)     __builtin_expect(!!(x),1)
#define unlikely(x)   __builtin_expect(!!(x),0)

#define inline        __inline__
#define always_inline __inline__ __attribute__ ((__always_inline__))
#define gnu_inline    __inline__ __attribute__ ((__gnu_inline__))
#define noinline      __attribute__((__noinline__))

#define noreturn      __attribute__((__noreturn__))

#define __packed      __attribute__((__packed__))

#define __weak        __attribute__((__weak__))

#if !CONFIG_CC_IS_CLANG || CONFIG_CLANG_VERSION >= 140000
# define nocall       __attribute__((__error__("Nonstandard ABI")))
#else
# define nocall
#endif

#ifdef CONFIG_XEN_IBT
# define cf_check     __attribute__((__cf_check__))
#else
# define cf_check
#endif

#if (!defined(__clang__) && (__GNUC__ == 4) && (__GNUC_MINOR__ < 5))
#define unreachable() do {} while (1)
#else
#define unreachable() __builtin_unreachable()
#endif

/*
 * Add the pseudo keyword 'fallthrough' so case statement blocks
 * must end with any of these keywords:
 *   break;
 *   fallthrough;
 *   goto <label>;
 *   return [expression];
 *
 *  gcc: https://gcc.gnu.org/onlinedocs/gcc/Statement-Attributes.html#Statement-Attributes
 */
#if (!defined(__clang__) && (__GNUC__ >= 7))
# define fallthrough        __attribute__((__fallthrough__))
#else
# define fallthrough        do {} while (0)  /* fallthrough */
#endif

#ifdef __clang__
/* Clang can replace some vars with new automatic ones that go in .data;
 * mark all explicit-segment vars 'used' to prevent that. */
#define __section(s)      __used __attribute__((__section__(s)))
#else
#define __section(s)      __attribute__((__section__(s)))
#endif
#define __used_section(s) __used __attribute__((__section__(s)))
#define __text_section(s) __attribute__((__section__(s)))

#define __aligned(a) __attribute__((__aligned__(a)))

#ifdef INIT_SECTIONS_ONLY
/*
 * For sources indicated to have only init code, make sure even
 * inline functions not expanded inline get placed in .init.text.
 */
#include <xen/init.h>
#define __inline__ __inline__ __init
#endif

#define __attribute_pure__  __attribute__((__pure__))
#define __attribute_const__ __attribute__((__const__))
#define __transparent__     __attribute__((__transparent_union__))

/*
 * The difference between the following two attributes is that __used is
 * intended to be used in cases where a reference to an identifier may be
 * invisible to the compiler (e.g. an inline assembly operand not listed
 * in the asm()'s operands), preventing the compiler from eliminating the
 * variable or function.
 * __maybe_unused otoh is to be used to merely prevent warnings (e.g. when
 * an identifier is used only inside a preprocessor conditional, yet putting
 * its declaration/definition inside another conditional would harm code
 * readability).
 */
#define __used         __attribute__((__used__))
#define __maybe_unused __attribute__((__unused__))

#define __must_check __attribute__((__warn_unused_result__))
#define __nonnull(...) __attribute__((__nonnull__(__VA_ARGS__)))

#define offsetof(a,b) __builtin_offsetof(a,b)

/**
 * sizeof_field(TYPE, MEMBER)
 *
 * @TYPE: The structure containing the field of interest
 * @MEMBER: The field to return the size of
 */
#define sizeof_field(TYPE, MEMBER) sizeof((((TYPE *)0)->MEMBER))

#if !defined(__STDC_VERSION__) || __STDC_VERSION__ < 201112L
#define alignof __alignof__
#endif

/* &a[0] degrades to a pointer: a different type from an array */
#define __must_be_array(a) \
  BUILD_BUG_ON_ZERO(__builtin_types_compatible_p(typeof(a), typeof(&(a)[0])))

#ifdef CONFIG_CC_HAS_VISIBILITY_ATTRIBUTE
/* Results in more efficient PIC code (no indirections through GOT or PLT). */
#pragma GCC visibility push(hidden)
#endif

/* Make the optimizer believe the variable can be manipulated arbitrarily. */
#define OPTIMIZER_HIDE_VAR(var) __asm__ ( "" : "+g" (var) )

/* This macro obfuscates arithmetic on a variable address so that gcc
   shouldn't recognize the original var, and make assumptions about it */
/*
 * Versions of the ppc64 compiler before 4.1 had a bug where use of
 * RELOC_HIDE could trash r30. The bug can be worked around by changing
 * the inline assembly constraint from =g to =r, in this particular
 * case either is valid.
 */
/* 1:定义了一个变量: unsigned long __ptr; */
/* 
   2:__asm__ ("" : "=r"(__ptr) : "0"(ptr)); ==> 没有实际的汇编指令，只是做一个输入到输出的数据传递，
                                            ==> "=r"(__ptr) 为将一个寄存器的值 赋值给 __ptr
                                            ==> "0"(ptr)    ptr为输入的参数，这个输入参数存储在一个寄存器中，这个寄存器与 "0"参数列表使用同一个寄存器，
                                                            也就是  __ptr 与  ptr 使用同一个寄存器 

这是一个C语言的宏定义，用于实现指针的重新定位和隐藏。该宏的目的是在某种情况下，为了避免编译器优化或内联，确保取得指针的实际值，然后加上一个偏移量off。现在，我会逐步解释这个宏的每一部分：

#define RELOC_HIDE(ptr, off): 定义一个名为RELOC_HIDE的宏，它接受两个参数：一个指针ptr和一个偏移量off。

({ ... }): 这是一个GNU C扩展，称为语句表达式。它允许你在宏中编写一个完整的代码块，并返回该代码块的最后一个表达式的值。这有助于在宏中编写更复杂的逻辑。

unsigned long __ptr;: 在语句表达式的内部，定义了一个unsigned long类型的变量__ptr。

__asm__ ("" : "=r"(__ptr) : "0"(ptr));: 这是一个内嵌汇编语句。它的目的是获取ptr指针的实际值并将其存储在__ptr中。

"": 空的汇编模板，意味着不执行任何汇编指令。
: "=r"(__ptr): 这是一个输出约束，表示将结果存储在__ptr中。=r意味着将结果存储在一个通用寄存器中。
: "0"(ptr): 这是一个输入约束，表示将ptr作为第一个操作数（因为输入和输出操作数都是通过数字索引的，而0代表第一个操作数）。由于它使用了与输出操作数相同的数字索引0，这意味着输入和输出都使用相同的寄存器，从而实现了ptr的值到__ptr的传递。
(typeof(ptr)) (__ptr + (off)): 最后，这个表达式将__ptr与偏移量off相加，并转换回ptr的原始类型。这样，你就得到了一个指向新位置的指针。

总结：这个宏的目的是获取ptr的实际地址值，然后加上一个偏移量off，从而得到一个新的地址，并返回该地址的指针。它可能用于避免编译器优化或内联，确保在某些上下文中得到预期的指针值。
*/
/* 参考 ==> 0:percpu变量的实现原理  */
#define RELOC_HIDE(ptr, off)                    \
  ({ unsigned long __ptr;                       \
    __asm__ ("" : "=r"(__ptr) : "0"(ptr));      \
    (typeof(ptr)) (__ptr + (off)); })

#if CONFIG_GCC_VERSION >= 110000 /* See gcc bug 100680. */
# define gcc11_wrap(x) RELOC_HIDE(x, 0)
#else
# define gcc11_wrap(x) (x)
#endif

#ifdef __GCC_ASM_FLAG_OUTPUTS__
# define ASM_FLAG_OUT(yes, no) yes
#else
# define ASM_FLAG_OUT(yes, no) no
#endif

/*
 * NB: we need to disable the gcc-compat warnings for clang in some places or
 * else it will complain with: "'break' is bound to loop, GCC binds it to
 * switch" when a switch is used inside of a while expression inside of a
 * switch statement, ie:
 *
 * switch ( ... )
 * {
 * case ...:
 *      while ( ({ int x; switch ( foo ) { case 1: x = 1; break; } x }) )
 *      {
 *              ...
 *
 * This has already been reported upstream:
 * http://bugs.llvm.org/show_bug.cgi?id=32595 
 */
#ifdef __clang__
# define CLANG_DISABLE_WARN_GCC_COMPAT_START                    \
    _Pragma("clang diagnostic push")                            \
    _Pragma("clang diagnostic ignored \"-Wgcc-compat\"")
# define CLANG_DISABLE_WARN_GCC_COMPAT_END                      \
    _Pragma("clang diagnostic pop")
#else
# define CLANG_DISABLE_WARN_GCC_COMPAT_START
# define CLANG_DISABLE_WARN_GCC_COMPAT_END
#endif

#endif /* __LINUX_COMPILER_H */
