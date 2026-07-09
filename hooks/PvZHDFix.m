// PvZHDFix.c - Standalone hook dylib para sideloading (sin jailbreak)
// Compilar con GitHub Actions: .github/workflows/build_ipa.yml
// Hooks implementados:
//   1. NSData/NSString swizzle -> LawnStrings.txt: "Acerca de"/"About" -> "Unlock All"
//   2. 7 SCNetworkReachability hooks via fishhook -> bloquea ads/red
//   3. NSURLConnection sync block
//   4. applyUnlocks() en constructor -> desbloquea todo al lanzar

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <SystemConfiguration/SCNetworkReachability.h>
#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include "fishhook.h"


// ============================================================
// Original function pointers
// ============================================================
static Boolean (*orig_SCNetworkReachabilityGetFlags)(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityFlags *flags
) = NULL;

static SCNetworkReachabilityRef (*orig_SCNetworkReachabilityCreateWithName)(
    CFAllocatorRef allocator,
    const char *nodename
) = NULL;

static SCNetworkReachabilityRef (*orig_SCNetworkReachabilityCreateWithAddress)(
    CFAllocatorRef allocator,
    const struct sockaddr *address
) = NULL;

static Boolean (*orig_SCNetworkReachabilitySetCallback)(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityCallBack callout,
    SCNetworkReachabilityContext *context
) = NULL;

static Boolean (*orig_SCNetworkReachabilityScheduleWithRunLoop)(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFStringRef runLoopMode
) = NULL;

static Boolean (*orig_SCNetworkReachabilityUnscheduleFromRunLoop)(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFStringRef runLoopMode
) = NULL;

static Boolean (*orig_SCNetworkReachabilitySetDispatchQueue)(
    SCNetworkReachabilityRef target,
    dispatch_queue_t queue
) = NULL;

static NSData *(*orig_NSURLConnection_sendSyncRequest)(Class, SEL, NSURLRequest *, NSURLResponse **, NSError **) = NULL;

// ============================================================
// Hooked functions
// ============================================================

// Makes the game think there's no internet connection
// This is the key fix - ad SDKs check reachability before making requests
Boolean hooked_SCNetworkReachabilityGetFlags(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityFlags *flags
) {
    // Return "not reachable" - flags = 0 means no connectivity
    if (flags) *flags = 0;
    return TRUE; // Success (no error, just not reachable)
}

// Prevent creation of reachability monitors entirely
SCNetworkReachabilityRef hooked_SCNetworkReachabilityCreateWithName(
    CFAllocatorRef allocator,
    const char *nodename
) {
    // Return NULL - no reachability object means no connectivity check
    return NULL;
}

SCNetworkReachabilityRef hooked_SCNetworkReachabilityCreateWithAddress(
    CFAllocatorRef allocator,
    const struct sockaddr *address
) {
    return NULL;
}

// No-op reachability callback registration
Boolean hooked_SCNetworkReachabilitySetCallback(
    SCNetworkReachabilityRef target,
    SCNetworkReachabilityCallBack callout,
    SCNetworkReachabilityContext *context
) {
    return TRUE;
}

Boolean hooked_SCNetworkReachabilityScheduleWithRunLoop(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFStringRef runLoopMode
) {
    return TRUE;
}

Boolean hooked_SCNetworkReachabilityUnscheduleFromRunLoop(
    SCNetworkReachabilityRef target,
    CFRunLoopRef runLoop,
    CFStringRef runLoopMode
) {
    return TRUE;
}

Boolean hooked_SCNetworkReachabilitySetDispatchQueue(
    SCNetworkReachabilityRef target,
    dispatch_queue_t queue
) {
    return TRUE;
}

static NSData *hooked_NSURLConnection_sendSyncRequest(Class self, SEL _cmd, NSURLRequest *request, NSURLResponse **response, NSError **error) {
    NSLog(@"[PvZHDFix] Blocked synchronous request: %@", request.URL);
    if (error) {
        *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    }
    return NULL;
}

// ============================================================
// LawnStrings.txt text patch
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

// NSData +dataWithContentsOfFile: hook
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
                if (newData) return newData;
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
                if (newData) return newData;
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
        if (patched != result) return patched;
    }
    return result;
}

// ============================================================
// Unlock all content via NSUserDefaults
// ============================================================
static void applyUnlocks(void) {
    @autoreleasepool {
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
        NSLog(@"[PvZHDFix] All content unlocked via NSUserDefaults");
    }
}



// ============================================================
// Constructor - runs when dylib is loaded
// ============================================================
__attribute__((constructor))
void PvZHDFix_Initialize(void) {
    @autoreleasepool {
        NSLog(@"[PvZHDFix] Loading hook dylib...");

        // 1. Hook SystemConfiguration reachability functions
        struct rebinding rebindings[] = {
            { "SCNetworkReachabilityGetFlags",
              hooked_SCNetworkReachabilityGetFlags,
              (void **)&orig_SCNetworkReachabilityGetFlags },

            { "SCNetworkReachabilityCreateWithName",
              hooked_SCNetworkReachabilityCreateWithName,
              (void **)&orig_SCNetworkReachabilityCreateWithName },

            { "SCNetworkReachabilityCreateWithAddress",
              hooked_SCNetworkReachabilityCreateWithAddress,
              (void **)&orig_SCNetworkReachabilityCreateWithAddress },

            { "SCNetworkReachabilitySetCallback",
              hooked_SCNetworkReachabilitySetCallback,
              (void **)&orig_SCNetworkReachabilitySetCallback },

            { "SCNetworkReachabilityScheduleWithRunLoop",
              hooked_SCNetworkReachabilityScheduleWithRunLoop,
              (void **)&orig_SCNetworkReachabilityScheduleWithRunLoop },

            { "SCNetworkReachabilityUnscheduleFromRunLoop",
              hooked_SCNetworkReachabilityUnscheduleFromRunLoop,
              (void **)&orig_SCNetworkReachabilityUnscheduleFromRunLoop },

            { "SCNetworkReachabilitySetDispatchQueue",
              hooked_SCNetworkReachabilitySetDispatchQueue,
              (void **)&orig_SCNetworkReachabilitySetDispatchQueue },
        };

        int result = rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));

        // 2. Hook NSURLConnection sync requests
        Method urlMethod = class_getClassMethod(
            [NSURLConnection class],
            @selector(sendSynchronousRequest:returningResponse:error:)
        );
        if (urlMethod) {
            orig_NSURLConnection_sendSyncRequest =
                (void *)method_getImplementation(urlMethod);
            method_setImplementation(urlMethod, (IMP)hooked_NSURLConnection_sendSyncRequest);
        }

        // 3. Hook NSData/NSString for LawnStrings.txt text patch
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

        // 4. Auto-unlock al arrancar
        applyUnlocks();

        if (result == 0) {
            NSLog(@"[PvZHDFix] ======================================");
            NSLog(@"[PvZHDFix] PvZHDFix Unlock All Mod cargado OK!");
            NSLog(@"[PvZHDFix] - Texto boton: 'Unlock All' (via NSData swizzle)");
            NSLog(@"[PvZHDFix] - Todo el contenido desbloqueado");
            NSLog(@"[PvZHDFix] ======================================");
        } else {
            NSLog(@"[PvZHDFix] Algunos hooks fallaron (fishhook result: %d)", result);
        }
    }
}
