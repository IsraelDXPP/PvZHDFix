# PvZ HD No Crash Fix

Plants vs Zombies HD Free (v2.4.0) crashes on launch or during gameplay when
internet is available because its ad SDKs try to reach dead/offline servers and
either hang or crash.

## Root Causes

1. **Ad SDK Network Reachability** — `SCNetworkReachability*` functions detect
   internet connectivity, causing ad SDKs to attempt network requests to
   dead/offline servers, resulting in hangs or crashes.

2. **SafariServices.framework Hard Link** — The binary links
   `SafariServices.framework` as a required (`LC_LOAD_DYLIB`) framework, which
   only exists on iOS 9+. On iPad Mini 1 running iOS 8, dyld cannot resolve
   this and crashes immediately at launch (after showing the launch image).

## Fixes

The fix consists of two parts:

### A) Binary Patching (patch_ipa.py)

Patches the Mach-O binary directly using LIEF:

1. **All 7 `SCNetworkReachability*` GOT entries** are redirected to custom
   ARM stubs that always return "not reachable" state:
   - `SCNetworkReachabilityGetFlags` → returns TRUE, *flags=0
   - `SCNetworkReachabilityCreateWithName` → returns NULL
   - `SCNetworkReachabilityCreateWithAddress` → returns NULL
   - `SCNetworkReachabilitySetCallback` → returns TRUE (no-op)
   - `SCNetworkReachabilityScheduleWithRunLoop` → returns TRUE (no-op)
   - `SCNetworkReachabilityUnscheduleFromRunLoop` → returns TRUE (no-op)
   - `SCNetworkReachabilitySetDispatchQueue` → returns TRUE (no-op)

2. **SafariServices.framework** changed from `LC_LOAD_DYLIB` to
   `LC_LOAD_WEAK_DYLIB` for iOS 8 compatibility.

3. **GoogleInteractiveMediaAds framework** also patched with the same stubs.

4. **Code signature** removed.

5. **Optional auto-sign** with `ldid` if available.

### B) Dylib Injection (for sideloading / jailbreak)

A standalone `PvZHDFix.dylib` using fishhook that hooks the same functions
at runtime. Also hooks `NSURLConnection` and `NSURLSession` to prevent
blocking network requests.

## Files

| File | Description |
|------|-------------|
| `patch_ipa.py` | **Main tool** — binary patching via LIEF (works on Linux) |
| `hooks.c` | C implementation using dyld interposing |
| `hooks.h` | Header for hook functions |
| `PvZHDFix.m` | Full hook dylib using fishhook |
| `Tweak.xm` | Jailbreak tweak (theos/Logos) |
| `fishhook.h` / `fishhook.c` | Facebook's fishhook library |
| `Makefile` | theos build file for jailbreak tweak |
| `control` | deb control file |
| `build_dylib.sh` | Build script for standalone dylib (macOS) |
| `inject_dylib.sh` | Inject dylib into binary |
| `repack_ipa.sh` | Full IPA repackaging script (macOS) |

## Usage (Linux — Recommended)

```bash
# Install LIEF
pip3 install lief

# Patch the IPA
./patch_ipa.py "PvZ Free HD 2.4.0 (829655975).ipa" PvZ_HD_NoCrash.ipa
```

The script:
1. Extracts the IPA
2. Patches the main binary and Google IMA framework
3. Makes SafariServices weak-linked
4. Removes code signatures
5. Signs with ldid (if available, for jailbroken devices)
6. Repacks into a new IPA

## Usage (macOS — Dylib Injection)

```bash
# Build the dylib
./build_dylib.sh

# Repack IPA
./repack_ipa.sh "PvZ Free HD 2.4.0 (829655975).ipa"
```

## Hooks Applied

| Function | Action |
|----------|--------|
| `SCNetworkReachabilityGetFlags` | Returns TRUE, flags=0 (not reachable) |
| `SCNetworkReachabilityCreateWithName` | Returns NULL |
| `SCNetworkReachabilityCreateWithAddress` | Returns NULL |
| `SCNetworkReachabilitySetCallback` | No-op, returns TRUE |
| `SCNetworkReachabilityScheduleWithRunLoop` | No-op, returns TRUE |
| `SCNetworkReachabilityUnscheduleFromRunLoop` | No-op, returns TRUE |
| `SCNetworkReachabilitySetDispatchQueue` | No-op, returns TRUE |
| `NSURLConnection +sendSynchronousRequest:` | Returns nil with "not connected" error |
| `NSURLSession dataTaskWithRequest:` | Returns nil |
| `NSURLSession dataTaskWithURL:` | Returns nil |
| `WKWebView loadRequest:` | Returns nil |

## iPad Mini 1 Compatibility

- Requires iOS 8.0+ (iPad Mini 1 supports up to iOS 9.3.5)
- SafariServices weak-linked for iOS 8 compatibility
- Binary includes ARMv7 (32-bit) slice for A5 chip

## License

fishhook is copyright (c) 2013, Facebook, Inc.
The hook code is provided under MIT license.
