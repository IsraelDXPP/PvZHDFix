// PvZHDFix.m - Standalone hook dylib para sideloading (sin jailbreak)
// Compilar con GitHub Actions: .github/workflows/build_ipa.yml
// Hooks:
//   1. UIButton setTitle:forState: swizzle -> "Acerca de" -> "Unlock All"
//   2. NSURLConnection sync block
//   3. applyUnlocks() en constructor -> desbloquea todo al lanzar
//   4. About button hook (armv7) -> applyUnlocks + alert
// NOTA: SCNetworkReachability es parcheado por patch_ipa.py en el binario, no aquí

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <libkern/OSCacheControl.h>


// ============================================================
// Original function pointers
// ============================================================
static NSData *(*orig_NSURLConnection_sendSyncRequest)(Class, SEL, NSURLRequest *, NSURLResponse **, NSError **) = NULL;

static NSData *hooked_NSURLConnection_sendSyncRequest(Class self, SEL _cmd, NSURLRequest *request,
                                                       NSURLResponse **response, NSError **error) {
    if (error) *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
    return NULL;
}

// ============================================================
// UIButton setTitle:forState: swizzle
// ============================================================
static void (*orig_setTitle_forState)(id, SEL, NSString *, UIControlState);
static void hook_setTitle_forState(id self, SEL _cmd, NSString *title, UIControlState state) {
    if ([title isEqualToString:@"Acerca DE"] || [title isEqualToString:@"Acerca de"]) {
        title = @"Unlock All";
    }
    orig_setTitle_forState(self, _cmd, title, state);
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
                                                         message:@"All game modes and levels have been unlocked!"
                                                        delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
    }
}

// Encode Thumb-2 BL T4 instruction (armv7)
static void encode_bl_thumb(uint16_t *out, uintptr_t src, uintptr_t dst) {
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

// Encode AArch64 BL (arm64)
static uint32_t encode_bl_arm64(uintptr_t src, uintptr_t dst) {
    int64_t offset = (int64_t)(dst - src);
    uint32_t imm26 = (uint32_t)(offset >> 2) & 0x03FFFFFF;
    return 0x94000000 | imm26;
}

// Encode AArch64 B (arm64)
static uint32_t encode_b_arm64(uintptr_t src, uintptr_t dst) {
    int64_t offset = (int64_t)(dst - src);
    uint32_t imm26 = (uint32_t)(offset >> 2) & 0x03FFFFFF;
    return 0x14000000 | imm26;
}

// armv7 trampoline: LDR R0, [PC, #0]; MOV PC, R0; <addr>
static void write_trampoline_thumb(uint16_t *tramp, uintptr_t hook_fn) {
    tramp[0] = 0x4800;
    tramp[1] = 0x4687;
    *(uint32_t *)(tramp + 2) = (uint32_t)hook_fn;
}

// arm64 trampoline: LDR X17, #8; BR X17; <addr>
// LDR X17, #8 = 0x58000051, BR X17 = 0xD61F0220
static void write_trampoline_arm64(uint32_t *tramp, uintptr_t hook_fn) {
    tramp[0] = 0x58000051;
    tramp[1] = 0xD61F0220;
    *(uintptr_t *)(tramp + 2) = hook_fn;
}

static int make_writable(vm_address_t addr) {
    vm_address_t page = addr & ~0xFFF;
    kern_return_t kr = vm_protect(mach_task_self(), page, 0x1000, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr == KERN_SUCCESS) return 1;
    kr = vm_protect(mach_task_self(), page, 0x1000, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    return kr == KERN_SUCCESS;
}

static int make_executable(vm_address_t addr) {
    vm_address_t page = addr & ~0xFFF;
    return vm_protect(mach_task_self(), page, 0x1000, FALSE, VM_PROT_READ | VM_PROT_EXECUTE) == KERN_SUCCESS;
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

static uintptr_t get_text_end(void) {
    const struct mach_header *hdr = _dyld_get_image_header(0);
    if (!hdr) return 0;
    bool is64 = (hdr->magic == MH_MAGIC_64);
    uintptr_t cmd_ptr = (uintptr_t)hdr + (is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
    uint32_t ncmds = hdr->ncmds;
    uint32_t seg_cmd = is64 ? LC_SEGMENT_64 : LC_SEGMENT;

    for (uint32_t i = 0; i < ncmds; i++) {
        uint32_t cmd = *(uint32_t *)cmd_ptr;
        if (cmd == seg_cmd) {
            const char *segname = (const char *)(cmd_ptr + 8);
            if (strncmp(segname, "__TEXT", 6) == 0) {
                uint64_t vmsize = is64 ? *(uint64_t *)(cmd_ptr + 32) : *(uint32_t *)(cmd_ptr + 28);
                return (uintptr_t)hdr + (uintptr_t)vmsize - (is64 ? 24 : 12);
            }
        }
        cmd_ptr += *(uint32_t *)(cmd_ptr + 4);
    }
    return 0;
}

static void install_about_hook(void) {
    uintptr_t header = (uintptr_t)_dyld_get_image_header(0);
    if (!header) { NSLog(@"[PvZHDFix] _dyld_get_image_header(0) is NULL"); return; }

    const struct mach_header *mh = (const struct mach_header *)header;
    bool is64 = (mh->magic == MH_MAGIC_64);
    NSLog(@"[PvZHDFix] pvz_base = 0x%x arch=%s", (unsigned int)header, is64 ? "arm64" : "armv7");

    uintptr_t hook_fn = (uintptr_t)&hook_about_button;

    if (is64) {
        // ========= ARM64 =========
        // NOTE: arm64 offset unknown - add here when found
        // The text patch and auto-unlock still work on arm64.
        // To find offset: search arm64 __TEXT for ADRP+ADD referencing CCLAbout/About string,
        // then find the BL that calls through to the About handler.
        NSLog(@"[PvZHDFix] arm64: About button hook not yet implemented (text + unlock OK)");
        return;
    }

    // ========= ARMV7 =========
    uintptr_t hook_target = header + 0x1E8580;

    uint8_t expected[] = {0x01, 0x99, 0x9D, 0xF8, 0x03, 0x20, 0x02, 0xF0};
    uint8_t actual[sizeof(expected)];
    memcpy(actual, (void *)hook_target, sizeof(actual));
    NSLog(@"[PvZHDFix] target=0x%x bytes: %02x %02x %02x %02x %02x %02x %02x %02x",
          (unsigned int)hook_target,
          actual[0], actual[1], actual[2], actual[3],
          actual[4], actual[5], actual[6], actual[7]);

    if (memcmp(actual, expected, sizeof(expected)) != 0) {
        NSLog(@"[PvZHDFix] Pattern mismatch - offset may be wrong for this binary version");
        return;
    }

    intptr_t bl_offset = (intptr_t)(hook_fn - (hook_target + 4));
    if (bl_offset < -16777216 || bl_offset > 16777215) {
        NSLog(@"[PvZHDFix] BL out of range (%d), writing trampoline", (int)bl_offset);
        uintptr_t tramp_addr = get_text_end();
        if (!tramp_addr) {
            NSLog(@"[PvZHDFix] Cannot find __TEXT end for trampoline");
            return;
        }
        uint16_t tramp[4];
        write_trampoline_thumb(tramp, hook_fn);
        if (!write_and_flush(tramp_addr, tramp, 8)) {
            NSLog(@"[PvZHDFix] Failed to write trampoline");
            return;
        }
        uint16_t bl[2];
        encode_bl_thumb(bl, hook_target, tramp_addr);
        if (!write_and_flush(hook_target, bl, 4)) {
            NSLog(@"[PvZHDFix] write_and_flush FAILED");
            return;
        }
        NSLog(@"[PvZHDFix] About button hooked OK (armv7, trampoline)");
        return;
    }

    uint16_t bl[2];
    encode_bl_thumb(bl, hook_target, hook_fn);
    NSLog(@"[PvZHDFix] BL=%04x %04x dist=%d fn=0x%x", bl[0], bl[1], (int)bl_offset, (unsigned int)hook_fn);

    if (!write_and_flush(hook_target, bl, 4)) {
        NSLog(@"[PvZHDFix] write_and_flush FAILED");
        return;
    }
    NSLog(@"[PvZHDFix] About button hooked OK (armv7)");
}

// ============================================================
// Constructor - runs when dylib is loaded
// ============================================================
__attribute__((constructor))
void PvZHDFix_Initialize(void) {
    @autoreleasepool {
        NSLog(@"[PvZHDFix] Loading hook dylib...");

        Method urlMethod = class_getClassMethod([NSURLConnection class], @selector(sendSynchronousRequest:returningResponse:error:));
        if (urlMethod) {
            orig_NSURLConnection_sendSyncRequest = (void *)method_getImplementation(urlMethod);
            method_setImplementation(urlMethod, (IMP)hooked_NSURLConnection_sendSyncRequest);
        }

        Class button = objc_getClass("UIButton");
        SEL titleSel = @selector(setTitle:forState:);
        Method titleMethod = class_getInstanceMethod(button, titleSel);
        if (titleMethod) {
            orig_setTitle_forState = (void*)method_getImplementation(titleMethod);
            method_setImplementation(titleMethod, (IMP)hook_setTitle_forState);
            NSLog(@"[PvZHDFix] UIButton setTitle:forState: swizzled");
        }

        install_about_hook();
        applyUnlocks();

        NSLog(@"[PvZHDFix] ======================================");
        NSLog(@"[PvZHDFix] PvZHDFix Unlock All Mod cargado OK!");
        NSLog(@"[PvZHDFix] - Texto boton: 'Unlock All' (via UIButton swizzle)");
        NSLog(@"[PvZHDFix] - Todo el contenido desbloqueado");
        NSLog(@"[PvZHDFix] - SCNetworkReachability trust patch_ipa.py");
        NSLog(@"[PvZHDFix] ======================================");
    }
}
