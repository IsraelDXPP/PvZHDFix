// PvZHDFix.m - Standalone hook dylib para sideloading (sin jailbreak)
// Compilar con GitHub Actions: .github/workflows/build_ipa.yml
// Hooks:
//   1. UIButton setTitle:forState: swizzle -> "Acerca de" -> "Unlock All"
//   2. applyUnlocks() en constructor -> desbloquea todo al lanzar
// NOTA: SCNetworkReachability es parcheado por patch_ipa.py en el binario, no aquí
// NOTA: NSURLConnection sync request no se bloquea aquí para evitar crashes

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <Foundation/Foundation.h>
#include <UIKit/UIKit.h>
#include <objc/runtime.h>

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
// UIControl sendAction:to:forEvent: swizzle -> intercept "Unlock All" tap
// ============================================================
static void (*orig_sendAction_to_forEvent)(id, SEL, SEL, id, UIEvent *);
static void hook_sendAction_to_forEvent(id self, SEL _cmd, SEL action, id target, UIEvent *event) {
    if ([self isKindOfClass:objc_getClass("UIButton")]) {
        NSString *title = [(UIButton *)self titleForState:UIControlStateNormal];
        if ([title isEqualToString:@"Unlock All"]) {
            applyUnlocks();
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Unlock All"
                                                             message:@"All game modes and levels have been unlocked!"
                                                            delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alert show];
            return;
        }
    }
    orig_sendAction_to_forEvent(self, _cmd, action, target, event);
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

        Class button = objc_getClass("UIButton");
        SEL titleSel = @selector(setTitle:forState:);
        Method titleMethod = class_getInstanceMethod(button, titleSel);
        if (titleMethod) {
            orig_setTitle_forState = (void*)method_getImplementation(titleMethod);
            method_setImplementation(titleMethod, (IMP)hook_setTitle_forState);
            NSLog(@"[PvZHDFix] UIButton setTitle:forState: swizzled");
        }

        Class control = objc_getClass("UIControl");
        SEL actionSel = @selector(sendAction:to:forEvent:);
        Method actionMethod = class_getInstanceMethod(control, actionSel);
        if (actionMethod) {
            orig_sendAction_to_forEvent = (void*)method_getImplementation(actionMethod);
            method_setImplementation(actionMethod, (IMP)hook_sendAction_to_forEvent);
            NSLog(@"[PvZHDFix] UIControl sendAction:to:forEvent: swizzled");
        }

        applyUnlocks();

        NSLog(@"[PvZHDFix] ======================================");
        NSLog(@"[PvZHDFix] PvZHDFix Unlock All Mod cargado OK!");
        NSLog(@"[PvZHDFix] - Texto boton: 'Unlock All' (via UIButton swizzle)");
        NSLog(@"[PvZHDFix] - Todo el contenido desbloqueado");
        NSLog(@"[PvZHDFix] ======================================");
    }
}
