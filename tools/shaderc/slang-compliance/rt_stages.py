#!/usr/bin/env python3
"""
Ray tracing shader-stage check for the bgfx Slang front-end.

bgfx has no stock ray tracing compiler, so unlike run.py (which checks Slang output
against the stock .sc compiler) this is a self-validation: for each RT stage it
compiles shaders/rt/rt_basic.slang with --type <stage> and checks that

  1. the compile succeeds,
  2. the envelope chunk magic is the expected <X>SH one for the stage,
  3. the embedded SPIR-V is valid (spirv-val, if available) and declares the
     RayTracingKHR capability and the expected OpEntryPoint execution model,
  4. the raygen stage reflects the RaytracingAccelerationStructure as an
     AccelerationStructure-descriptor uniform (not dropped).

Usage:
  rt_stages.py [--shaderc PATH] [--bgfx-root PATH] [-v]
Exit code is non-zero if any check fails. SPIR-V validation is skipped (not failed)
when spirv-val is not on PATH.
"""
import argparse, os, shutil, struct, subprocess, sys, tempfile

# stage --type -> (magic leading char, SPIR-V OpEntryPoint execution model token)
STAGES = [
    ("raygeneration", "R", "RayGenerationKHR"),
    ("intersection",  "I", "IntersectionKHR"),
    ("anyhit",        "A", "AnyHitKHR"),
    ("closesthit",    "H", "ClosestHitKHR"),
    ("miss",          "M", "MissKHR"),
    ("callable",      "L", "CallableKHR"),
]

ACCEL_STRUCT_ID = 0x1000  # descriptorTypeToId(DescriptorType::AccelerationStructure)

def parse_envelope(path):
    d = open(path, "rb").read()
    o = 0
    def u8():
        nonlocal o; v = d[o]; o += 1; return v
    def u16():
        nonlocal o; v = struct.unpack_from("<H", d, o)[0]; o += 2; return v
    def u32():
        nonlocal o; v = struct.unpack_from("<I", d, o)[0]; o += 4; return v
    magic = u32()
    r = {"magicChar": chr(magic & 0xff), "ver": (magic >> 24) & 0xff}
    u32(); u32()                      # hashIn, hashOut (0 for RT)
    count = u16()
    r["uniforms"] = []
    for _ in range(count):
        n = u8(); name = d[o:o+n].decode("latin1"); o += n
        t = u8(); num = u8(); reg = u16(); regc = u16(); u8(); u8(); u16()
        r["uniforms"].append((name, regc))
    shaderSize = u32()
    r["spv"] = d[o:o+shaderSize]
    return r

def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--shaderc", default=os.path.join(here, "../../bin/darwin/shaderc"))
    ap.add_argument("--bgfx-root", default=os.path.abspath(os.path.join(here, "../../..")))
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    shaderc = os.path.abspath(args.shaderc)
    root = os.path.abspath(args.bgfx_root)
    src = os.path.join(here, "shaders", "rt", "rt_basic.slang")
    spirv_val = shutil.which("spirv-val")
    spirv_dis = shutil.which("spirv-dis")

    tmp = tempfile.mkdtemp(prefix="rt-stages-")
    npass = nfail = 0
    for stage, magic_char, model in STAGES:
        label = f"rt_basic [{stage}]"
        out = os.path.join(tmp, stage + ".bin")
        rc, log = run([shaderc, "--lang", "slang", "-f", src, "--type", stage,
                       "-p", "spirv", "--platform", "linux",
                       "-i", os.path.join(root, "src"), "-o", out])
        if rc != 0 or not os.path.exists(out):
            print(f"FAIL {label}: compile failed\n{log.strip()}"); nfail += 1; continue

        env = parse_envelope(out)
        problems = []
        if env["magicChar"] != magic_char:
            problems.append(f"magic '{env['magicChar']}SH' != expected '{magic_char}SH'")

        spv = os.path.join(tmp, stage + ".spv")
        open(spv, "wb").write(env["spv"])
        if spirv_val:
            vrc, vlog = run([spirv_val, "--target-env", "vulkan1.2", spv])
            if vrc != 0:
                problems.append("spirv-val failed: " + vlog.strip())
        if spirv_dis:
            _, dis = run([spirv_dis, spv])
            if "RayTracingKHR" not in dis:
                problems.append("missing OpCapability RayTracingKHR")
            if model not in dis:
                problems.append(f"missing OpEntryPoint {model}")

        if stage == "raygeneration":
            accel = [n for (n, regc) in env["uniforms"] if regc == ACCEL_STRUCT_ID]
            if not accel:
                problems.append("acceleration structure not reflected (dropped?)")

        if problems:
            print(f"FAIL {label}")
            for p in problems:
                print(f"       {p}")
            nfail += 1
        else:
            extra = "" if spirv_val else " (spirv-val skipped)"
            print(f"PASS {label}{extra}")
            npass += 1

    print(f"\n{npass} passed, {nfail} failed")
    return 1 if nfail else 0

if __name__ == "__main__":
    sys.exit(main())
