// PvZHDFix.c - Standalone hook dylib para sideloading (sin jailbreak)
// Compilar con GitHub Actions: .github/workflows/build_ipa.yml
// Hooks implementados:
//   1. NSData/NSString swizzle -> LawnStrings.txt: "Acerca de"/"About" -> "Unlock All"
//   2. 7 SCNetworkReachability hooks via fishhook -> bloquea ads/red
//   3. NSURLConnection sync block
//   4. applyUnlocks() en constructor -> desbloquea todo al lanzar
//   5. Hook raw del callback del boton About -> muestra alert + unlock

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <SystemConfiguration/SCNetworkReachability.h>
#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
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
                if (newData) return [newData retain];
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
                if (newData) return [newData retain];
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
        if (patched != result) return [patched retain];
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
// Alert helper - muestra en el hilo principal
// ============================================================
static void showUnlockAlert(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Unlock All"
            message:@"Todo el contenido ha sido desbloqueado!\n(All levels, modes & content unlocked)"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        if (root) {
            while (root.presentedViewController) root = root.presentedViewController;
            [root presentViewController:alert animated:YES completion:nil];
        }
    });
}

// ============================================================
// Raw hook del boton About:
//   ARM64: lambda offset 0x1001f1ad4 (base sin ASLR)
//   ARMv7: lambda offset 0x001e4581  (Thumb LSB=1)
// Tecnica: vm_protect RWX + patch prologo con trampolin
// ============================================================

static void (*orig_about_button_callback)(void) = NULL;

static void hook_about_button(void) {
    NSLog(@"[PvZHDFix] About button interceptado -> Unlock All");
    applyUnlocks();
    showUnlockAlert();
    // No llamamos al original -> suprime la pantalla About
}

static int pvz_write_hook(void *target, void *hook_fn, void **orig_out) {
#if defined(__arm64__)
    const size_t TRAMP_SIZE = 16;
    // ARM64: LDR X16, #8 ; BR X16 ; .quad addr
    uint8_t tramp[16];
    tramp[0]=0x50; tramp[1]=0x00; tramp[2]=0x00; tramp[3]=0x58; // LDR X16, #8
    tramp[4]=0x00; tramp[5]=0x02; tramp[6]=0x1F; tramp[7]=0xD6; // BR X16
    uint64_t ha = (uint64_t)hook_fn;
    memcpy(tramp+8, &ha, 8);
#elif defined(__arm__)
    const size_t TRAMP_SIZE = 12;
    // ARMv7 Thumb2: MOVW/MOVT R12, addr ; BX R12 ; NOP
    uint32_t ha = (uint32_t)(uintptr_t)hook_fn;
    uint16_t lo = ha & 0xFFFF, hi = (ha >> 16) & 0xFFFF;
    // Thumb2 MOVW encoding for R12:
    //   halfword1: 0xF240 | (i<<10) | imm4
    //   halfword2: 0x0C00 | (imm3<<12) | imm8
    uint16_t mov_hw1 = 0xF240 | ((lo>>11&1)<<10) | (lo>>12);
    uint16_t mov_hw2 = 0x0C00 | ((lo>>8&0x7)<<12) | (lo&0xFF);
    uint16_t movt_hw1 = 0xF2C0 | ((hi>>11&1)<<10) | (hi>>12);
    uint16_t movt_hw2 = 0x0C00 | ((hi>>8&0x7)<<12) | (hi&0xFF);
    uint8_t tramp[12];
    memcpy(tramp+0, &mov_hw1,  2); memcpy(tramp+2,  &mov_hw2,  2);
    memcpy(tramp+4, &movt_hw1, 2); memcpy(tramp+6,  &movt_hw2, 2);
    tramp[8]=0x60; tramp[9]=0x47;   // BX R12
    tramp[10]=0x00; tramp[11]=0xBF; // NOP
    // Para Thumb, el puntero real es target & ~1
    target = (void *)((uintptr_t)target & ~1UL);
#else
    return -1;
#endif

    if (orig_out) {
        // Asignar buffer ejecutable para el original
        vm_address_t orig_buf = 0;
        vm_allocate(mach_task_self(), &orig_buf, TRAMP_SIZE + 16, VM_FLAGS_ANYWHERE);
        memcpy((void *)orig_buf, target, TRAMP_SIZE);
#if defined(__arm64__)
        // Append trampoline back to (target+TRAMP_SIZE)
        uint8_t back[16];
        back[0]=0x50; back[1]=0x00; back[2]=0x00; back[3]=0x58;
        back[4]=0x00; back[5]=0x02; back[6]=0x1F; back[7]=0xD6;
        uint64_t back_addr = (uint64_t)target + TRAMP_SIZE;
        memcpy(back+8, &back_addr, 8);
        memcpy((uint8_t *)orig_buf + TRAMP_SIZE, back, 16);
#endif
        vm_protect(mach_task_self(), orig_buf, TRAMP_SIZE+16, false, VM_PROT_READ|VM_PROT_EXECUTE);
        *orig_out = (void *)orig_buf;
    }

    // Hacer pagina writable
    vm_address_t page = (vm_address_t)target & ~(vm_page_size-1);
    kern_return_t kr = vm_protect(mach_task_self(), page, vm_page_size,
                                  false, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        NSLog(@"[PvZHDFix] vm_protect(RW) fallo: %d", kr);
        return -1;
    }

    memcpy(target, tramp, TRAMP_SIZE);

    vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ|VM_PROT_EXECUTE);
    sys_icache_invalidate(target, TRAMP_SIZE);
    return 0;
}

static void hookAboutButton(intptr_t slide) {
#if defined(__arm64__)
    const uintptr_t OFFSET = 0x1001f1ad4ULL;
    void *target = (void *)(OFFSET + (uint64_t)slide);
#elif defined(__arm__)
    // ARMv7 Thumb offset (LSB=1 indica modo Thumb)
    // Encontrado buscando el patron lambda de initButton<CCLAbout>
    const uintptr_t OFFSET = 0x001e4581UL;
    void *target = (void *)(OFFSET + (uint32_t)slide);
#else
    return;
#endif
    NSLog(@"[PvZHDFix] Hooking About callback @ %p (slide=0x%lx)", target, (long)slide);
    int ret = pvz_write_hook(target, (void *)hook_about_button,
                              (void **)&orig_about_button_callback);
    if (ret == 0)
        NSLog(@"[PvZHDFix] About button hook OK");
    else
        NSLog(@"[PvZHDFix] About button hook FALLO ret=%d", ret);
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

        // 4. Hook raw del boton About (presionar -> Unlock All + alert)
        intptr_t slide = _dyld_get_image_vmaddr_slide(0);
        hookAboutButton(slide);

        // 5. Auto-unlock al arrancar (sideloading: sin acceso al callback del boton)
        applyUnlocks();

        if (result == 0) {
            NSLog(@"[PvZHDFix] ======================================");
            NSLog(@"[PvZHDFix] PvZHDFix Unlock All Mod cargado OK!");
            NSLog(@"[PvZHDFix] - Texto boton: 'Unlock All' (via NSData swizzle)");
            NSLog(@"[PvZHDFix] - Callback boton hookeado (hook raw)");
            NSLog(@"[PvZHDFix] - Todo el contenido desbloqueado");
            NSLog(@"[PvZHDFix] ======================================");
        } else {
            NSLog(@"[PvZHDFix] Algunos hooks fallaron (fishhook result: %d)", result);
        }
    }
}
