#include <ucontext.h>
#include <machine/fpu.h>

namespace factor
{

inline static void *ucontext_stack_pointer(void *uap)
{
        ucontext_t *ucontext = (ucontext_t *)uap;
        return (void *)ucontext->uc_mcontext.mc_rsp;
}

inline static unsigned int uap_fpu_status(void *uap)
{
        ucontext_t *ucontext = (ucontext_t *)uap;
        if (uap->uc_mcontext.mc_fpformat == _MC_FPFMT_XMM) {
            struct savexmm *xmm = (struct savexmm *)(&ucontext->uc_mcontext.mc_fpstate);
            return xmm->en_sw | xmm->en_mxcsr;
        } else
            return 0;
}

inline static void uap_clear_fpu_status(void *uap)
{
        ucontext_t *ucontext = (ucontext_t *)uap;
        if (uap->uc_mcontext.mc_fpformat == _MC_FPFMT_XMM) {
            struct savexmm *xmm = (struct savexmm *)(&ucontext->uc_mcontext.mc_fpstate);
            xmm->en_sw = 0;
            xmm->en_mxcsr &= 0xffffffc0;
        }
}

#define UAP_PROGRAM_COUNTER(ucontext) (((ucontext_t *)(ucontext))->uc_mcontext.mc_rip)

}
