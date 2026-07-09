// PvZHDFix.c - Standalone hook dylib para sideloading (sin jailbreak)
// Compilar con GitHub Actions: .github/workflows/build_ipa.yml
// Hooks implementados:
//   1. NSData/NSString swizzle -> LawnStrings.txt: "Acerca de"/"About" -> "Unlock All"
//   2. 7 SCNetworkReachability hooks via fishhook -> bloquea ads/red
//   3. NSURLConnection sync block
//   4. applyUnlocks() en constructor -> desbloquea todo al lanzar
//   5. Raw BL hook (pattern-search in __TEXT) -> About button -> applyUnlocks + alert

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <SystemConfiguration/SCNetworkReachability.h>
#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <libkern/OSCacheControl.h>
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
// About button hook - replaces legal button with "Unlock All"
// ============================================================

static void hook_about_button(void) {
    @autoreleasepool {
        applyUnlocks();

        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Unlock All"
                                                         message:@"All game modes and levels have been unlocked! Enjoy!"
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
    }
}

// Encode Thumb-2 BL T4 instruction
static void encode_bl(uint16_t *out, uintptr_t src, uintptr_t dst) {
    int32_t offset = (int32_t)(dst - (src + 4));
    uint32_t u = (uint32_t)offset & 0x1FFFFFF;
    uint8_t S = (u >> 24) & 1;
    uint8_t I1 = (u >> 23) & 1;
    uint8_t I2 = (u >> 22) & 1;
    uint16_t imm10 = (u >> 12) & 0x3FF;
    uint16_t imm11 = (u >> 1) & 0x7FF;
    uint8_t J1 = 1 ^ (I1 ^ S);
    uint8_t J2 = 1 ^ (I2 ^ S);
    out[0] = 0xF000 | (S << 10) | imm10;
    out[1] = (1 << 15) | (1 << 14) | (J1 << 13) | (1 << 12) | (J2 << 11) | imm11;
}

// Write trampoline: PUSH {R0, LR}; LDR R0, [PC, #0]; .word hook_fn; STR R0, [SP, #4]; POP {R0, PC}
static void write_trampoline(uint16_t *tramp, uintptr_t hook_fn) {
    tramp[0] = 0xB501;
    tramp[1] = 0x4800;
    *(uint32_t *)(tramp + 2) = (uint32_t)hook_fn;
    tramp[4] = 0x9001;
    tramp[5] = 0xBD01;
}

static uintptr_t find_pattern_in_text(const uint8_t *pattern, size_t len) {
    uintptr_t header = (uintptr_t)_dyld_get_image_header(0);
    if (!header) return 0;
    uintptr_t cmd_ptr = header + sizeof(struct mach_header);
    uint32_t ncmds = *(uint32_t *)(header + 16);
    uintptr_t text_start = 0, text_size = 0;

    for (uint32_t i = 0; i < ncmds; i++) {
        uint32_t cmd = *(uint32_t *)cmd_ptr;
        uint32_t cmdsize = *(uint32_t *)(cmd_ptr + 4);
        if (cmd == LC_SEGMENT) {
            if (memcmp((void *)(cmd_ptr + 8), "__TEXT\0\0\0\0\0\0\0\0\0\0", 16) == 0) {
                text_start = header;
                text_size = *(uint32_t *)(cmd_ptr + 0x1C);
                break;
            }
        }
        cmd_ptr += cmdsize;
    }
    if (!text_start || !text_size) return 0;

    for (uintptr_t p = text_start; p + len <= text_start + text_size; p += 2)
        if (memcmp((void *)p, pattern, len) == 0) return p;
    return 0;
}

static int make_writable(vm_address_t addr) {
    vm_address_t page = addr & ~0xFFF;
    kern_return_t kr = vm_protect(mach_task_self(), page, 0x1000, FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr == KERN_SUCCESS) return 1;
    kr = vm_protect(mach_task_self(), page, 0x1000, FALSE,
                    VM_PROT_READ | VM_PROT_WRITE);
    return kr == KERN_SUCCESS;
}

static int make_executable(vm_address_t addr) {
    vm_address_t page = addr & ~0xFFF;
    return vm_protect(mach_task_self(), page, 0x1000, FALSE,
                      VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS;
}

static int write_and_flush(uintptr_t addr, const void *data, size_t len) {
    if (!make_writable(addr)) return 0;
    memcpy((void *)addr, data, len);
    if (memcmp((void *)addr, data, len) != 0) return 0;
    if (!make_executable(addr)) return 0;
    sys_dcache_flush((void *)addr, len);
    sys_icache_invalidate((void *)addr, len);
    return 1;
}

static void install_about_hook(void) {
    uintptr_t header = (uintptr_t)_dyld_get_image_header(0);
    if (!header) { NSLog(@"[PvZHDFix] _dyld_get_image_header(0) is NULL"); return; }
    NSLog(@"[PvZHDFix] pvz_base = 0x%x", (unsigned int)header);

    uintptr_t hook_fn = (uintptr_t)&hook_about_button;
    uintptr_t hook_target = header + 0x1E4580;

    // Verify pattern
    uint8_t expected[] = {0x01, 0x99, 0x9D, 0xF8, 0x03, 0x20, 0x02, 0xF0};
    uint8_t actual[sizeof(expected)];
    memcpy(actual, (void *)hook_target, sizeof(actual));
    NSLog(@"[PvZHDFix] target=0x%x bytes: %02x %02x %02x %02x %02x %02x %02x %02x",
          (unsigned int)hook_target,
          actual[0], actual[1], actual[2], actual[3],
          actual[4], actual[5], actual[6], actual[7]);

    if (memcmp(actual, expected, sizeof(expected)) != 0) {
        NSLog(@"[PvZHDFix] Pattern mismatch, searching __TEXT...");
        hook_target = find_pattern_in_text(expected, sizeof(expected));
        if (!hook_target) {
            NSLog(@"[PvZHDFix] Pattern not found, giving up");
            return;
        }
        NSLog(@"[PvZHDFix] Found pattern at 0x%x", (unsigned int)hook_target);
    }

    intptr_t bl_offset = (intptr_t)(hook_fn - (hook_target + 4));
    if (bl_offset < -16777216 || bl_offset > 16777215) {
        NSLog(@"[PvZHDFix] BL out of range (%d), trampoline needed", (int)bl_offset);
        return;
    }

    uint16_t bl[2];
    encode_bl(bl, hook_target, hook_fn);
    NSLog(@"[PvZHDFix] BL=%04x %04x dist=%d fn=0x%x", bl[0], bl[1],
          (int)bl_offset, (unsigned int)hook_fn);

    if (!write_and_flush(hook_target, bl, 4)) {
        NSLog(@"[PvZHDFix] write_and_flush FAILED");
        return;
    }
    NSLog(@"[PvZHDFix] About button hooked OK");
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

        // 4. Hook About button to "Unlock All"
        install_about_hook();

        // 5. Auto-unlock al arrancar
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
