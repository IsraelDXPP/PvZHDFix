#import <Foundation/Foundation.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#import <substrate.h>
#import <mach-o/dyld.h>

// ============================================================
// LawnStrings.txt patcher
// ============================================================
static NSString *patchLawnStrings(NSString *content) {
    NSRange keyRange = [content rangeOfString:@"[BTN_LEGAL_ABOUT]"];
    if (keyRange.location == NSNotFound)
        return content;

    NSUInteger i = keyRange.location + keyRange.length;
    NSCharacterSet *nl = [NSCharacterSet newlineCharacterSet];
    while (i < content.length && [nl characterIsMember:[content characterAtIndex:i]])
        i++;

    NSUInteger lineEnd = i;
    while (lineEnd < content.length && ![nl characterIsMember:[content characterAtIndex:lineEnd]])
        lineEnd++;

    return [content stringByReplacingCharactersInRange:NSMakeRange(i, lineEnd - i)
                                            withString:@"Unlock All"];
}

// ============================================================
// NSData / NSString hooks to intercept LawnStrings.txt reads
// ============================================================
static NSData *(*orig_dataWithContentsOfFile)(Class, SEL, NSString *);
static NSData *hook_dataWithContentsOfFile(Class self, SEL _cmd, NSString *path) {
    NSData *data = orig_dataWithContentsOfFile(self, _cmd, path);
    if (data && [path hasSuffix:@"LawnStrings.txt"]) {
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
        if (!content) content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (content) {
            NSString *patched = patchLawnStrings(content);
            if (patched != content) {
                NSData *newData = [patched dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
                if (newData) {
                    return [newData retain];
                }
            }
        }
    }
    return data;
}

static NSData *(*orig_dataWithContentsOfFile_options_error)(Class, SEL, NSString *, NSDataReadingOptions, NSError **);
static NSData *hook_dataWithContentsOfFile_options_error(Class self, SEL _cmd, NSString *path,
                                                          NSDataReadingOptions options, NSError **error) {
    NSData *data = orig_dataWithContentsOfFile_options_error(self, _cmd, path, options, error);
    if (data && [path hasSuffix:@"LawnStrings.txt"]) {
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding];
        if (!content) content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (content) {
            NSString *patched = patchLawnStrings(content);
            if (patched != content) {
                NSData *newData = [patched dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
                if (newData) {
                    return [newData retain];
                }
            }
        }
    }
    return data;
}

static NSString *(*orig_stringWithContentsOfFile_encoding_error)(Class, SEL, NSString *, NSStringEncoding, NSError **);
static NSString *hook_stringWithContentsOfFile_encoding_error(Class self, SEL _cmd, NSString *path,
                                                               NSStringEncoding enc, NSError **error) {
    NSString *result = orig_stringWithContentsOfFile_encoding_error(self, _cmd, path, enc, error);
    if (result && [path hasSuffix:@"LawnStrings.txt"]) {
        NSString *patched = patchLawnStrings(result);
        if (patched != result) {
            return [patched retain];
        }
    }
    return result;
}

// ============================================================
// SCNetworkReachability hooks
// ============================================================
static Boolean (*orig_SCNetworkReachabilityGetFlags)(
    SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags);
Boolean hook_SCNetworkReachabilityGetFlags(
    SCNetworkReachabilityRef target, SCNetworkReachabilityFlags *flags) {
    if (flags) *flags = 2;
    return TRUE;
}

static SCNetworkReachabilityRef (*orig_SCNetworkReachabilityCreateWithName)(
    CFAllocatorRef allocator, const char *nodename);
SCNetworkReachabilityRef hook_SCNetworkReachabilityCreateWithName(
    CFAllocatorRef allocator, const char *nodename) {
    return NULL;
}

static SCNetworkReachabilityRef (*orig_SCNetworkReachabilityCreateWithAddress)(
    CFAllocatorRef allocator, const struct sockaddr *address);
SCNetworkReachabilityRef hook_SCNetworkReachabilityCreateWithAddress(
    CFAllocatorRef allocator, const struct sockaddr *address) {
    return NULL;
}

static Boolean (*orig_SCNetworkReachabilitySetCallback)(
    SCNetworkReachabilityRef target, SCNetworkReachabilityCallBack callout,
    SCNetworkReachabilityContext *context);
Boolean hook_SCNetworkReachabilitySetCallback(
    SCNetworkReachabilityRef target, SCNetworkReachabilityCallBack callout,
    SCNetworkReachabilityContext *context) {
    return TRUE;
}

static Boolean (*orig_SCNetworkReachabilityScheduleWithRunLoop)(
    SCNetworkReachabilityRef target, CFRunLoopRef runLoop, CFStringRef runLoopMode);
Boolean hook_SCNetworkReachabilityScheduleWithRunLoop(
    SCNetworkReachabilityRef target, CFRunLoopRef runLoop, CFStringRef runLoopMode) {
    return TRUE;
}

static Boolean (*orig_SCNetworkReachabilityUnscheduleFromRunLoop)(
    SCNetworkReachabilityRef target, CFRunLoopRef runLoop, CFStringRef runLoopMode);
Boolean hook_SCNetworkReachabilityUnscheduleFromRunLoop(
    SCNetworkReachabilityRef target, CFRunLoopRef runLoop, CFStringRef runLoopMode) {
    return TRUE;
}

static Boolean (*orig_SCNetworkReachabilitySetDispatchQueue)(
    SCNetworkReachabilityRef target, dispatch_queue_t queue);
Boolean hook_SCNetworkReachabilitySetDispatchQueue(
    SCNetworkReachabilityRef target, dispatch_queue_t queue) {
    return TRUE;
}

// ============================================================
// Unlock all content via NSUserDefaults
// ============================================================
static void applyUnlocks() {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

    [defs setBool:YES forKey:@"hasUnlockedMinigames"];
    [defs setBool:YES forKey:@"hasUnlockedMoreWays"];
    [defs setBool:YES forKey:@"hasUnlockedPuzzleMode"];
    [defs setBool:YES forKey:@"hasUnlockedSurvivalMode"];

    [defs setBool:YES forKey:@"hasNewMiniGame"];
    [defs setBool:YES forKey:@"hasNewSurvival"];
    [defs setBool:YES forKey:@"hasNewVasebreaker"];
    [defs setBool:YES forKey:@"hasNewIZombie"];

    [defs setBool:YES forKey:@"newContentMini"];
    [defs setBool:YES forKey:@"newContentPuzzle"];
    [defs setBool:YES forKey:@"newContentSurvival"];
    [defs setBool:YES forKey:@"newContentQuickPlay"];

    [defs setInteger:0 forKey:@"numLockedQuickPlayLevels"];
    [defs setInteger:0 forKey:@"numLockedSurvivalLevels"];
    [defs setBool:YES forKey:@"survivalCompleted"];
    [defs setBool:YES forKey:@"bonusGameAccessShown"];
    [defs setBool:YES forKey:@"bonusGameFtueShown"];
    [defs setBool:YES forKey:@"freeBonusGameAccessShown"];
    [defs setBool:YES forKey:@"hasUnlockedZenGarden"];
    [defs setBool:YES forKey:@"adventure2Completed"];
    [defs setBool:YES forKey:@"adventureComplete"];

    [defs synchronize];
    NSLog(@"[PvZHDFix] All content unlocked");
}

// ============================================================
// About button callback hook
// Address: 0x1001f1ad4 (ARM64 __text)
// This is the std::function::__func::__call() vtable entry
// for HasMenuActions::initButton<CCLAbout>
// ============================================================
static void (*orig_about_callback)(void);

void hook_about_callback() {
    applyUnlocks();

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Unlock All"
            message:@"All levels, modes, and content have been unlocked!"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];

        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        if (root) {
            [root presentViewController:alert animated:YES completion:nil];
        }
    });
}

// ============================================================
// MSHook via C helper (Theos %group syntax would be cleaner,
// but raw C hooks are more portable)
// ============================================================
static void installHooks() {
    intptr_t slide = _dyld_get_image_vmaddr_slide(0);

    // --- NSData / NSString hooks for LawnStrings.txt text replacement ---
    Class nsdata = objc_getClass("NSData");
    SEL sel1 = @selector(dataWithContentsOfFile:);
    Method m1 = class_getClassMethod(nsdata, sel1);
    if (m1) {
        orig_dataWithContentsOfFile = (void*)method_getImplementation(m1);
        method_setImplementation(m1, (IMP)hook_dataWithContentsOfFile);
    }

    SEL sel2 = @selector(dataWithContentsOfFile:options:error:);
    Method m2 = class_getClassMethod(nsdata, sel2);
    if (m2) {
        orig_dataWithContentsOfFile_options_error = (void*)method_getImplementation(m2);
        method_setImplementation(m2, (IMP)hook_dataWithContentsOfFile_options_error);
    }

    Class nsstring = objc_getClass("NSString");
    SEL sel3 = @selector(stringWithContentsOfFile:encoding:error:);
    Method m3 = class_getClassMethod(nsstring, sel3);
    if (m3) {
        orig_stringWithContentsOfFile_encoding_error = (void*)method_getImplementation(m3);
        method_setImplementation(m3, (IMP)hook_stringWithContentsOfFile_encoding_error);
    }

    // --- Reachability hooks ---
    MSHookFunction((void*)SCNetworkReachabilityGetFlags,
        (void*)hook_SCNetworkReachabilityGetFlags,
        (void**)&orig_SCNetworkReachabilityGetFlags);
    MSHookFunction((void*)SCNetworkReachabilityCreateWithName,
        (void*)hook_SCNetworkReachabilityCreateWithName,
        (void**)&orig_SCNetworkReachabilityCreateWithName);
    MSHookFunction((void*)SCNetworkReachabilityCreateWithAddress,
        (void*)hook_SCNetworkReachabilityCreateWithAddress,
        (void**)&orig_SCNetworkReachabilityCreateWithAddress);
    MSHookFunction((void*)SCNetworkReachabilitySetCallback,
        (void*)hook_SCNetworkReachabilitySetCallback,
        (void**)&orig_SCNetworkReachabilitySetCallback);
    MSHookFunction((void*)SCNetworkReachabilityScheduleWithRunLoop,
        (void*)hook_SCNetworkReachabilityScheduleWithRunLoop,
        (void**)&orig_SCNetworkReachabilityScheduleWithRunLoop);
    MSHookFunction((void*)SCNetworkReachabilityUnscheduleFromRunLoop,
        (void*)hook_SCNetworkReachabilityUnscheduleFromRunLoop,
        (void**)&orig_SCNetworkReachabilityUnscheduleFromRunLoop);
    MSHookFunction((void*)SCNetworkReachabilitySetDispatchQueue,
        (void*)hook_SCNetworkReachabilitySetDispatchQueue,
        (void**)&orig_SCNetworkReachabilitySetDispatchQueue);

    // --- About button callback hook ---
    void* about_func = (void*)(0x1001f1ad4 + slide);
    MSHookFunction(about_func,
        (void*)hook_about_callback,
        (void**)&orig_about_callback);

    NSLog(@"[PvZHDFix] Hooks installed: text patch + unlock on About press");
}

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        installHooks();
    }
}
