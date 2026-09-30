#ifndef AICORE_WEAK_BRIDGE_SHIM_H
#define AICORE_WEAK_BRIDGE_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int32_t AICKCoreAIWeakSymbolPresent(void);
int32_t AICKCoreAIWeakIsAvailable(void);

#ifdef __cplusplus
}
#endif

#endif
