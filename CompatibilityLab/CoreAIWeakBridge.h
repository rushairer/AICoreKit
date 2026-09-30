#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (*AICKCoreAIGenerateCompletion)(
    void * _Nullable context,
    const char * _Nullable responseJSON,
    int32_t status
);

FOUNDATION_EXPORT int32_t AICKCoreAIIsAvailable(void)
    API_AVAILABLE(ios(27.0));

FOUNDATION_EXPORT void AICKCoreAIGenerate(
    const char *requestJSON,
    const char *modelPath,
    void * _Nullable context,
    AICKCoreAIGenerateCompletion completion
) API_AVAILABLE(ios(27.0));

NS_ASSUME_NONNULL_END
