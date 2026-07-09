#!/usr/bin/env python3
"""
PvZ HD No-Crash Fix - Binary Patching
=======================================

For main binary:
  - SafariServices -> WEAK_DYLIB
  - Only GetFlags patched -> returns reachable (age verification works)

For GoogleInteractiveMediaAds:
  - All 7 SCNetworkReachability functions patched -> blocked

No bundle modifications; keeps AgeVerification.bundle intact.
"""

import lief
import struct
import os
import sys
import shutil
import tempfile
import zipfile

# ============================================================
# ARM64 stubs
# ============================================================

# Sets *flags=kSCNetworkReachabilityFlagsReachable (0x02), returns TRUE
ARM64_GETFLAGS = bytes([
    0x42, 0x00, 0x00, 0xB8,  # STR W2, [X1]   ; *flags = 2 (reachable)
    0x20, 0x00, 0x80, 0x52,  # MOV W0, #1       ; return TRUE
    0xC0, 0x03, 0x5F, 0xD6,  # RET
])

# Returns TRUE (for SetCallback, ScheduleWithRunLoop, etc.)
ARM64_RETURN_TRUE = bytes([
    0x20, 0x00, 0x80, 0x52,  # MOV W0, #1
    0xC0, 0x03, 0x5F, 0xD6,  # RET
])

# Returns NULL (for CreateWithName, CreateWithAddress)
ARM64_RETURN_NULL = bytes([
    0x00, 0x00, 0x80, 0x52,  # MOV W0, #0
    0xC0, 0x03, 0x5F, 0xD6,  # RET
])

# ============================================================
# ARMv7 stubs
# ============================================================

# Sets *flags=kSCNetworkReachabilityFlagsReachable (0x02), returns TRUE
ARMV7_GETFLAGS = bytes([
    0x02, 0x20, 0xA0, 0xE3,  # MOV R2, #2
    0x00, 0x20, 0x81, 0xE5,  # STR R2, [R1]    ; *flags = 2
    0x01, 0x00, 0xA0, 0xE3,  # MOV R0, #1       ; return TRUE
    0x1E, 0xFF, 0x2F, 0xE1,  # BX LR
])

# Returns TRUE
ARMV7_RETURN_TRUE = bytes([
    0x01, 0x00, 0xA0, 0xE3,  # MOV R0, #1
    0x1E, 0xFF, 0x2F, 0xE1,  # BX LR
])

# Returns NULL
ARMV7_RETURN_NULL = bytes([
    0x00, 0x00, 0xA0, 0xE3,  # MOV R0, #0
    0x1E, 0xFF, 0x2F, 0xE1,  # BX LR
])

# Full set of stubs (all 7 functions, no connectivity)
STUBS_FULL = {
    "SCNetworkReachabilityGetFlags":           {"arm64": ARM64_GETFLAGS, "armv7": ARMV7_GETFLAGS},
    "SCNetworkReachabilityCreateWithName":     {"arm64": ARM64_RETURN_NULL, "armv7": ARMV7_RETURN_NULL},
    "SCNetworkReachabilityCreateWithAddress":  {"arm64": ARM64_RETURN_NULL, "armv7": ARMV7_RETURN_NULL},
    "SCNetworkReachabilitySetCallback":        {"arm64": ARM64_RETURN_TRUE, "armv7": ARMV7_RETURN_TRUE},
    "SCNetworkReachabilityScheduleWithRunLoop":{"arm64": ARM64_RETURN_TRUE, "armv7": ARMV7_RETURN_TRUE},
    "SCNetworkReachabilityUnscheduleFromRunLoop":{"arm64": ARM64_RETURN_TRUE, "armv7": ARMV7_RETURN_TRUE},
    "SCNetworkReachabilitySetDispatchQueue":   {"arm64": ARM64_RETURN_TRUE, "armv7": ARMV7_RETURN_TRUE},
}

# Minimal set: only GetFlags -> reachable (other functions use real impl)
STUBS_MIN = {
    "SCNetworkReachabilityGetFlags":           {"arm64": ARM64_GETFLAGS, "armv7": ARMV7_GETFLAGS},
}


def _get_arch(slice_):
    return "ARM64" if str(slice_.header.cpu_type) == 'CPU_TYPE.ARM64' else "ARMv7"


def _embed_stubs(slice_, stubs_dict):
    """Embed stubs into __stub_helper (or __text) and return {func_name: addr}."""
    arch = _get_arch(slice_)
    arch_key = arch.lower()
    addrs = {}

    section = slice_.get_section("__stub_helper")
    if not section:
        section = slice_.get_section("__text")
    if not section:
        print(f"  [{arch}] No __stub_helper or __text section found!")
        return addrs

    total = sum(len(stubs_dict[n][arch_key]) for n in stubs_dict)
    pad = (4 - (section.size % 4)) % 4
    try:
        slice_.extend_section(section, section.size + pad + total)
    except Exception:
        slice_.extend(section, total + pad)

    offset = section.size - total
    for name in stubs_dict:
        stub = stubs_dict[name][arch_key]
        addr = section.virtual_address + offset
        slice_.patch_address(addr, list(stub))
        verify = bytes(slice_.get_content_from_virtual_address(addr, len(stub)))
        assert verify == stub, f"Stub verify failed for {name} at {addr:x}"
        addrs[name] = addr
        offset += len(stub)

    return addrs


def _patch_bindings(slice_, stub_addrs):
    """Redirect matching GOT entries to our stubs."""
    arch = _get_arch(slice_)
    patched = 0

    if not slice_.has_dyld_info:
        print(f"  [{arch}] No dyld info, skipping bindings")
        return False

    for binding in slice_.dyld_info.bindings:
        try:
            sym = binding.symbol
        except AttributeError:
            continue
        if not sym:
            continue
        for func_name, stub_addr in stub_addrs.items():
            if func_name in sym.name:
                if 'ARM64' in arch:
                    ptr = struct.pack('<Q', stub_addr)
                    slice_.patch_address(binding.address, list(ptr))
                else:
                    ptr = struct.pack('<I', stub_addr & 0xFFFFFFFF)
                    slice_.patch_address(binding.address, list(ptr))

                current = bytes(slice_.get_content_from_virtual_address(binding.address, len(ptr)))
                val = struct.unpack('<Q' if 'ARM64' in arch else '<I', current)[0]
                if val != stub_addr:
                    print(f"  [{arch}] WARNING: verify failed {func_name} @ 0x{binding.address:x}")
                else:
                    print(f"  [{arch}] Patched {func_name} @ 0x{binding.address:x} -> stub 0x{stub_addr:x}")
                    patched += 1
                break

    return patched


def _make_safari_services_weak(slice_):
    arch = _get_arch(slice_)
    for cmd in slice_.commands:
        if 'DylibCommand' in str(type(cmd)) and 'SafariServices' in cmd.name:
            if str(cmd.command) == 'TYPE.LOAD_DYLIB':
                cmd.command = 0x80000018
                print(f"  [{arch}] SafariServices -> LOAD_WEAK_DYLIB")
                return True
    return False


def patch_macho(fat_binary, output_path, stubs_dict):
    """Patch all slices: SafariServices weak + reachability stubs from stubs_dict."""
    for idx in range(len(fat_binary)):
        slice_ = fat_binary[idx]
        arch = _get_arch(slice_)
        print(f"\n  Processing slice {idx}: {arch}")

        _make_safari_services_weak(slice_)

        stub_addrs = _embed_stubs(slice_, stubs_dict)
        if stub_addrs:
            count = _patch_bindings(slice_, stub_addrs)
            print(f"  [{arch}] Patched {count} GOT entries")
        else:
            print(f"  [{arch}] No stubs to embed")

        if slice_.has_code_signature:
            slice_.remove_signature()
            print(f"  [{arch}] Code signature removed")

    fat_binary.write(output_path)
    print(f"\n  Written to {output_path}")

# ============================================================
# Dylib injection via LIEF
# ============================================================

def inject_dylib(app_dir, binary_path, dylib_src):
    """
    Copies dylib to Frameworks/, adds @rpath/PvZHDFix.dylib LC_LOAD_DYLIB
    and @executable_path/Frameworks rpath to the main binary.
    """
    dylib_name = os.path.basename(dylib_src)
    frameworks_dir = os.path.join(app_dir, "Frameworks")
    os.makedirs(frameworks_dir, exist_ok=True)
    dst = os.path.join(frameworks_dir, dylib_name)
    shutil.copy2(dylib_src, dst)
    print(f"  Copied {dylib_name} to Frameworks/")

    fat = lief.MachO.parse(binary_path)
    rpath_val = "@executable_path/Frameworks"
    dylib_val = f"@rpath/{dylib_name}"

    for slice_ in fat:
        arch = _get_arch(slice_)

        # Add rpath if not already present
        existing_rpaths = []
        for cmd in slice_.commands:
            if str(cmd.command) == 'COMMAND_TYPES.RPATH':
                try:
                    existing_rpaths.append(cmd.path)
                except Exception:
                    pass
        if rpath_val not in existing_rpaths:
            rp = lief.MachO.RPathCommand.create(rpath_val)
            slice_.add(rp)
            print(f"  [{arch}] Added rpath: {rpath_val}")
        else:
            print(f"  [{arch}] rpath already present")

        # Add LC_LOAD_DYLIB if not already present
        existing_libs = [str(lib.name) for lib in slice_.libraries]
        if not any(dylib_name in lib for lib in existing_libs):
            dylib_cmd = lief.MachO.DylibCommand.create(dylib_val)
            slice_.add(dylib_cmd)
            print(f"  [{arch}] Added LC_LOAD_DYLIB: {dylib_val}")
        else:
            print(f"  [{arch}] LC_LOAD_DYLIB already present")

        if slice_.has_code_signature:
            slice_.remove_signature()

    fat.write(binary_path)
    print(f"  Binary updated with dylib injection")

    # Also sign the dylib with ldid
    ldid_path = next((p for p in [
        os.path.join(os.path.dirname(os.path.realpath(__file__)), "ldid"),
        shutil.which("ldid"),
        shutil.which("ldid2"),
    ] if p and os.path.isfile(p)), None)
    if ldid_path:
        os.system(f"{ldid_path} -S \"{dst}\"")
        print(f"  Signed {dylib_name} with ldid")



def main():
    if len(sys.argv) < 2:
        print("Usage: ./patch_ipa.py input.ipa [output.ipa]")
        sys.exit(1)

    input_ipa = sys.argv[1]
    output_ipa = sys.argv[2] if len(sys.argv) > 2 else "PvZ_HD_NoCrash.ipa"

    if not os.path.exists(input_ipa):
        print(f"ERROR: Input IPA not found: {input_ipa}")
        sys.exit(1)

    tmp = tempfile.mkdtemp(prefix="pvzpatch_")
    print(f"Extracting {input_ipa} to {tmp}")

    with zipfile.ZipFile(input_ipa, 'r') as z:
        z.extractall(tmp)

    payload = os.path.join(tmp, "Payload")
    app_dirs = [d for d in os.listdir(payload) if d.endswith('.app')]
    if not app_dirs:
        print("ERROR: No .app found in Payload")
        sys.exit(1)

    app_dir = os.path.join(payload, app_dirs[0])
    binary_path = os.path.join(app_dir, os.path.splitext(app_dirs[0])[0])

    print(f"\nApp: {app_dir}")
    print(f"Binary: {binary_path}")

    # Patch main binary: only GetFlags -> reachable
    print("\n=== Patching main binary (minimal: GetFlags -> reachable) ===")
    fat = lief.MachO.parse(binary_path)
    patch_macho(fat, binary_path, STUBS_MIN)

    # Inject PvZHDFix.dylib if present (compiled by GitHub Actions)
    dylib_src = os.path.join(os.path.dirname(os.path.realpath(__file__)), "PvZHDFix.dylib")
    if os.path.exists(dylib_src):
        print("\n=== Inyectando PvZHDFix.dylib (mod Unlock All) ===")
        inject_dylib(app_dir, binary_path, dylib_src)
    else:
        print("\nNOTE: PvZHDFix.dylib no encontrado — skipping dylib injection.")
        print("      Compila con GitHub Actions para inyectar los hooks de runtime.")

    # Patch Google IMA framework: all 7 functions -> blocked
    gima_path = os.path.join(app_dir, "Frameworks",
                             "GoogleInteractiveMediaAds.framework",
                             "GoogleInteractiveMediaAds")
    if os.path.exists(gima_path):
        print("\n=== Patching GoogleInteractiveMediaAds (full: all 7 -> blocked) ===")
        fat = lief.MachO.parse(gima_path)
        patch_macho(fat, gima_path, STUBS_FULL)
    else:
        print("\nGoogleInteractiveMediaAds not found, skipping")

    # Remove _CodeSignature directory
    cs_dir = os.path.join(app_dir, "_CodeSignature")
    if os.path.exists(cs_dir):
        shutil.rmtree(cs_dir)
        print("\nRemoved _CodeSignature directory")

    # AgeVerification.bundle is kept intact

    # Clean up code sig leftovers
    for f in os.listdir(app_dir):
        if f.startswith("CodeResources") or f == "embedded.mobileprovision":
            p = os.path.join(app_dir, f)
            if os.path.isfile(p):
                os.remove(p)
                print(f"Removed {f}")

    # Sign with ldid
    ldid_candidates = [
        os.path.join(os.path.dirname(os.path.realpath(__file__)), "ldid"),
        shutil.which("ldid"),
        shutil.which("ldid2"),
        "/tmp/ldid-build/ldid2",
        "/tmp/ldid",
    ]
    ldid_path = next((p for p in ldid_candidates if p and os.path.isfile(p)), None)

    if ldid_path:
        print(f"\n=== Signing with ldid ({ldid_path}) ===")
        try:
            entitlements = os.path.join(app_dir, "Entitlements.plist")
            cmd = f"{ldid_path} -S{entitlements} {app_dir}"
            ret = os.system(cmd)
            if ret == 0:
                print("  Signed via app directory")
            else:
                for root, dirs, files in os.walk(app_dir):
                    for f in files:
                        fpath = os.path.join(root, f)
                        try:
                            with open(fpath, 'rb') as fp:
                                magic = fp.read(4)
                                if magic in (b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe',
                                             b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe',
                                             b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'):
                                    ent = entitlements if 'Framework' not in fpath else ""
                                    sub = os.system(f"{ldid_path} -S{ent} \"{fpath}\"")
                                    print(f"  Signed {f} (ret={sub // 256})")
                        except (IOError, OSError):
                            pass
            cs_dir = os.path.join(app_dir, "_CodeSignature")
            os.makedirs(cs_dir, exist_ok=True)
            with open(os.path.join(cs_dir, "CodeResources"), 'w') as cr:
                cr.write('<?xml version="1.0" encoding="UTF-8"?>\n'
                         '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
                         '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
                         '<plist version="1.0"><dict><key>files</key><dict/>'
                         '<key>files2</key><dict/><key>rules</key><dict>'
                         '<key>^.*</key><true/><key>^.*\\.lproj/</key><true/>'
                         '</dict><key>rules2</key><dict><key>.*</key><true/>'
                         '<key>.*\\.lproj/</key><true/></dict></dict></plist>')
            print("  _CodeSignature directory created")
        except Exception as e:
            print(f"  ldid signing failed: {e}")
    else:
        print("\nNOTE: ldid not found -- skipping signing.")
        print("      Install ldid: apt install ldid, or compile from source.")

    # Repack IPA
    print(f"\n=== Repacking IPA ===")
    output_path = os.path.join(os.getcwd(), output_ipa)
    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(tmp):
            for f in files:
                fpath = os.path.join(root, f)
                arcname = os.path.relpath(fpath, tmp)
                z.write(fpath, arcname)

    shutil.rmtree(tmp)

    print(f"\n=== Done! ===")
    print(f"Output: {output_path}")
    print()
    print("Install via sideloading or directly on jailbroken device.")


if __name__ == "__main__":
    main()
