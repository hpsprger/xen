/* SPDX-License-Identifier: GPL-2.0 */
#include <xen/percpu.h>
#include <xen/cpu.h>
#include <xen/init.h>
#include <xen/mm.h>
#include <xen/rcupdate.h>

#if 0
你看链接脚本中  __per_cpu_start  与 __per_cpu_data_end 的定义如下 
也就是在 __per_cpu_start ~ __per_cpu_data_end 之间，存放了很多的段
  .bss : {                     /* BSS */
       __bss_start = .;
       *(.bss.stack_aligned)
       . = ALIGN(PAGE_SIZE);
       *(.bss.page_aligned)
       . = ALIGN(PAGE_SIZE);
       __per_cpu_start = .;
       *(.bss.percpu.page_aligned)
       *(.bss.percpu)
       . = ALIGN(SMP_CACHE_BYTES);
       *(.bss.percpu.read_mostly)
       . = ALIGN(SMP_CACHE_BYTES);
       __per_cpu_data_end = .;
       *(.bss .bss.*)
       . = ALIGN(POINTER_ALIGN);
       __bss_end = .;
  } :text
  _end = . ;
#endif 

unsigned long __per_cpu_offset[NR_CPUS];
#define INVALID_PERCPU_AREA (-(long)__per_cpu_start)
#define PERCPU_ORDER (get_order_from_bytes(__per_cpu_data_end-__per_cpu_start))

//void __init percpu_init_areas(void)
void  percpu_init_areas(void)
{
    unsigned int cpu;
    /* NR_CPUS ==> 看 config NR_CPUS 的描述 ==> ARM & qemu 应该要配置为4才对 ==> 目前.config中看到的是128个核 */
    /* 这个太大了，估计是这里配置的太大了，所以我刚开始qemu运行xen的时候，才感觉怎么XEN那么吃内存啊，修改下配置试试 */
    /* make menuconfig 中 我选中使用 QEMU aarch virt machine support ==> 选了这个平台后，发现NR_CPUS 还是128，所以必须要手动修改 (4) Maximum number of CPUs */
    for ( cpu = 1; cpu < NR_CPUS; cpu++ )
        /* 这里就是给这个数组赋值一个 初始化值 */
        __per_cpu_offset[cpu] = INVALID_PERCPU_AREA;
}

static int init_percpu_area(unsigned int cpu)
{
    char *p;
    if ( __per_cpu_offset[cpu] != INVALID_PERCPU_AREA )
        return -EBUSY;
    if ( (p = alloc_xenheap_pages(PERCPU_ORDER, 0)) == NULL )
        return -ENOMEM;
    memset(p, 0, __per_cpu_data_end - __per_cpu_start);
    __per_cpu_offset[cpu] = p - __per_cpu_start;
    return 0;
}

struct free_info {
    unsigned int cpu;
    struct rcu_head rcu;
};
static DEFINE_PER_CPU(struct free_info, free_info);

static void _free_percpu_area(struct rcu_head *head)
{
    struct free_info *info = container_of(head, struct free_info, rcu);
    unsigned int cpu = info->cpu;
    char *p = __per_cpu_start + __per_cpu_offset[cpu];
    free_xenheap_pages(p, PERCPU_ORDER);
    __per_cpu_offset[cpu] = INVALID_PERCPU_AREA;
}

static void free_percpu_area(unsigned int cpu)
{
    struct free_info *info = &per_cpu(free_info, cpu);
    info->cpu = cpu;
    call_rcu(&info->rcu, _free_percpu_area);
}

static int cpu_percpu_callback(
    struct notifier_block *nfb, unsigned long action, void *hcpu)
{
    unsigned int cpu = (unsigned long)hcpu;
    int rc = 0;

    switch ( action )
    {
    case CPU_UP_PREPARE:
        rc = init_percpu_area(cpu);
        break;
    case CPU_UP_CANCELED:
    case CPU_DEAD:
        free_percpu_area(cpu);
        break;
    default:
        break;
    }

    return notifier_from_errno(rc);
}

static struct notifier_block cpu_percpu_nfb = {
    .notifier_call = cpu_percpu_callback,
    .priority = 100 /* highest priority */
};

static int __init percpu_presmp_init(void)
{
    register_cpu_notifier(&cpu_percpu_nfb);
    return 0;
}
presmp_initcall(percpu_presmp_init);
