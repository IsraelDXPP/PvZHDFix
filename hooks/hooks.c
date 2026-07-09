#include <stdio.h>
#include <stdbool.h>
#include <sys/types.h>
#include <SystemConfiguration/SCNetworkReachability.h>

// Function pointer to store the original SCNetworkReachabilityGetFlags
static Boolean (*original_SCNetworkReachabilityGetFlags)(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityFlags *flags
) = NULL;

// Replacement function: always returns "not reachable"
Boolean hooked_SCNetworkReachabilityGetFlags(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityFlags *flags
) {
    if (flags) {
        *flags = 0; // No flags set = not reachable
    }
    return TRUE; // Success
}

// Replacement function: always returns NULL (creates no reachability object)
SCNetworkReachabilityRef hooked_SCNetworkReachabilityCreateWithName(
    CFAllocatorRef allocator,
    const char *nodename
) {
    return NULL;
}

// Replacement function: always returns NULL
SCNetworkReachabilityRef hooked_SCNetworkReachabilityCreateWithAddress(
    CFAllocatorRef allocator,
    const struct sockaddr *address
) {
    return NULL;
}

// Replacement function: no-op
Boolean hooked_SCNetworkReachabilitySetCallback(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityCallBack callout,
    SCNetworkReachabilityContext *context
) {
    return TRUE;
}

// Replacement function: no-op
Boolean hooked_SCNetworkReachabilityScheduleWithRunLoop(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFStringRef runLoopMode
) {
    return TRUE;
}

// Replacement function: no-op
Boolean hooked_SCNetworkReachabilityUnscheduleFromRunLoop(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFStringRef runLoopMode
) {
    return TRUE;
}

// Replacement function: no-op
Boolean hooked_SCNetworkReachabilitySetDispatchQueue(
    SCNetworkReachabilityRef target,
    dispatch_queue_t queue
) {
    return TRUE;
}

// Interpose section - tells dyld to replace the original functions
// with our hooked versions at load time
__attribute__((used, section("__DATA,__interpose")))
struct {
    const void *replacement;
    const void *original;
} interpose_entries[] = {
    { (const void *)hooked_SCNetworkReachabilityGetFlags,       (const void *)SCNetworkReachabilityGetFlags },
    { (const void *)hooked_SCNetworkReachabilityCreateWithName, (const void *)SCNetworkReachabilityCreateWithName },
    { (const void *)hooked_SCNetworkReachabilityCreateWithAddress, (const void *)SCNetworkReachabilityCreateWithAddress },
    { (const void *)hooked_SCNetworkReachabilitySetCallback,    (const void *)SCNetworkReachabilitySetCallback },
    { (const void *)hooked_SCNetworkReachabilityScheduleWithRunLoop, (const void *)SCNetworkReachabilityScheduleWithRunLoop },
    { (const void *)hooked_SCNetworkReachabilityUnscheduleFromRunLoop, (const void *)SCNetworkReachabilityUnscheduleFromRunLoop },
    { (const void *)hooked_SCNetworkReachabilitySetDispatchQueue, (const void *)SCNetworkReachabilitySetDispatchQueue },
};
