#ifndef PvZHDFix_hooks_h
#define PvZHDFix_hooks_h

#include <stdbool.h>
#include <SystemConfiguration/SCNetworkReachability.h>

Boolean hooked_SCNetworkReachabilityGetFlags(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityFlags *flags
);

SCNetworkReachabilityRef hooked_SCNetworkReachabilityCreateWithName(
    CFAllocatorRef allocator,
    const char *nodename
);

SCNetworkReachabilityRef hooked_SCNetworkReachabilityCreateWithAddress(
    CFAllocatorRef allocator,
    const struct sockaddr *address
);

Boolean hooked_SCNetworkReachabilitySetCallback(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityCallBack callout,
    SCNetworkReachabilityContext *context
);

Boolean hooked_SCNetworkReachabilityScheduleWithRunLoop(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFStringRef runLoopMode
);

Boolean hooked_SCNetworkReachabilityUnscheduleFromRunLoop(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFStringRef runLoopMode
);

Boolean hooked_SCNetworkReachabilitySetDispatchQueue(
    SCNetworkReachabilityRef target,
    dispatch_queue_t queue
);

#endif
