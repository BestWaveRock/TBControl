#include <mach/mach_types.h>
#include <libkern/libkern.h>
#include <i386/proc_reg.h>

extern void mp_rendezvous_no_intrs(void (*action_func)(void *), void *arg);

static const uint64_t disableTurboBoostMask = 0x4000000000ULL;

static void disable_tb(__unused void *param) {
    wrmsr64(MSR_IA32_MISC_ENABLE, rdmsr64(MSR_IA32_MISC_ENABLE) | disableTurboBoostMask);
}

static void enable_tb(__unused void *param) {
    wrmsr64(MSR_IA32_MISC_ENABLE, rdmsr64(MSR_IA32_MISC_ENABLE) & ~disableTurboBoostMask);
}

static kern_return_t start(kmod_info_t *ki, void *d) {
    uint64_t prev = rdmsr64(MSR_IA32_MISC_ENABLE);
    mp_rendezvous_no_intrs(disable_tb, NULL);
    printf("TBControl: Disabled Turbo Boost %llx -> %llx\n", prev, rdmsr64(MSR_IA32_MISC_ENABLE));
    return KERN_SUCCESS;
}

static kern_return_t stop(kmod_info_t *ki, void *d) {
    uint64_t prev = rdmsr64(MSR_IA32_MISC_ENABLE);
    mp_rendezvous_no_intrs(enable_tb, NULL);
    printf("TBControl: Re-enabled Turbo Boost %llx -> %llx\n", prev, rdmsr64(MSR_IA32_MISC_ENABLE));
    return KERN_SUCCESS;
}

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);

KMOD_EXPLICIT_DECL(com.tbcontrol.DisableTurboBoost, "1.0.0", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = start;
__private_extern__ kmod_stop_func_t  *_antimain = stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
