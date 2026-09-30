#include "AICoreWeakBridgeShim.h"

int main(void) {
    if (!AICKCoreAIWeakSymbolPresent()) {
        return 0;
    }

    (void)AICKCoreAIWeakIsAvailable();
    return 0;
}
