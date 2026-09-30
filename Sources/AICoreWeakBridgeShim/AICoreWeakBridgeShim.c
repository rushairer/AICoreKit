#include "AICoreWeakBridgeShim.h"

#if defined(__APPLE__)
extern int32_t AICKCoreAIIsAvailable(void) __attribute__((weak_import));
#endif

int32_t AICKCoreAIWeakSymbolPresent(void) {
#if defined(__APPLE__)
    return AICKCoreAIIsAvailable != 0 ? 1 : 0;
#else
    return 0;
#endif
}

int32_t AICKCoreAIWeakIsAvailable(void) {
#if defined(__APPLE__)
    if (AICKCoreAIIsAvailable == 0) {
        return 0;
    }
    return AICKCoreAIIsAvailable();
#else
    return 0;
#endif
}
