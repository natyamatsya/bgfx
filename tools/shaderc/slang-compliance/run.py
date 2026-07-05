#!/usr/bin/env python3
"""
Slang shader compliance test runner for bgfx.

For each Slang port under shaders/<example>/<name>.slang, and for each stage the
matching bgfx example provides (examples/<example>/{vs,fs,cs}_<name>.sc), this:
  1. compiles the stock .sc to a SPIR-V envelope with the stock front-end,
  2. compiles the .slang port to a SPIR-V envelope with --lang slang,
  3. compares the reflection fields AND the SPIR-V matrix decorations.

Reflection alone does not reveal a transposed matrix, so the matrix-decoration
check is a required second gate (see the column-major layout fix in
shaderc_slang.cpp).

Usage:
  run.py [--shaderc PATH] [--bgfx-root PATH] [--filter SUBSTR] [-v]
Exit code is non-zero if any case fails.
"""
import argparse, os, struct, subprocess, sys, tempfile

STAGES = [("vertex", "vs"), ("fragment", "fs"), ("compute", "cs")]

# Compilation targets. Each Slang port is checked against the stock .sc through the
# same target, so both sides go through the identical backend (SPIR-V, or Metal's
# SPIRV-Cross MSL path). The code blob (SPIR-V words vs MSL text) is never compared;
# only the reflection the runtime consumes.
TARGETS = {
    "spirv": {"profile": "spirv", "platform": "linux"},
    "metal": {"profile": "metal", "platform": "osx"},
}

# ---- envelope + SPIR-V parsing -------------------------------------------------
U = {0: "Sampler", 1: "End", 2: "Vec4", 3: "Mat3", 4: "Mat4"}
DECOR = {4: "RowMajor", 5: "ColMajor", 7: "MatrixStride"}

def parse_envelope(path, metal=False):
    d = open(path, "rb").read()
    o = 0
    def u8():
        nonlocal o; v = d[o]; o += 1; return v
    def u16():
        nonlocal o; v = struct.unpack_from("<H", d, o)[0]; o += 2; return v
    def u32():
        nonlocal o; v = struct.unpack_from("<I", d, o)[0]; o += 4; return v
    r = {}
    magic = u32()
    r["magic"] = bytes([magic & 0xff, (magic >> 8) & 0xff, (magic >> 16) & 0xff]).decode("latin1")
    r["ver"] = (magic >> 24) & 0xff
    r["hashIn"] = u32(); r["hashOut"] = u32()
    count = u16()
    r["uniforms"] = []
    for _ in range(count):
        n = u8(); name = d[o:o+n].decode("latin1"); o += n
        t = u8(); num = u8(); reg = u16(); regc = u16(); tc = u8(); td = u8(); tf = u16()
        r["uniforms"].append((name, U.get(t & ~0xF0, t & ~0xF0), t & 0xF0, num, reg, regc, tc, td, tf))
    # The Metal compute envelope inserts a 3x u16 threadgroup-size trailer between the
    # uniform table and the code blob (see compileMetalShaderFromSpirv); skip it.
    if metal and r["magic"] == "CSH":
        r["localSize"] = tuple(u16() for _ in range(3))
    shaderSize = u32()
    spv = d[o:o+shaderSize]; o += shaderSize
    o += 1                                    # nul
    numAttr = u8()
    r["attrs"] = sorted(u16() for _ in range(numAttr))   # compare as a set (location order differs by compiler)
    r["size"] = u16()
    r["matrix"] = matrix_decorations(spv)
    return r

def matrix_decorations(spv):
    if len(spv) < 20:
        return []
    words = struct.unpack_from("<%dI" % (len(spv) // 4), spv, 0)
    if words[0] != 0x07230203:
        return []
    i, found = 5, []
    while i < len(words):
        wc = words[i] >> 16; op = words[i] & 0xFFFF
        if wc == 0:
            break
        if op == 72 and words[i+3] in DECOR:      # OpMemberDecorate: struct, member, decoration, [extra]
            extra = words[i+4] if wc >= 5 else None
            found.append((words[i+2], DECOR[words[i+3]], extra))
        i += wc
    return sorted(found)

# ---- compile helpers -----------------------------------------------------------
def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr)

def compile_stock(shaderc, root, ex, stock_base, stage, out, target):
    sc = os.path.join(root, "examples", ex, f"{stock_base}.sc")
    vdef = os.path.join(root, "examples", ex, "varying.def.sc")
    # The example's own dir goes first: shaderc resolves #include "..." against the
    # working directory, and bgfx's real build runs make from inside the example
    # (scripts/shader.mk adds only -i ../src/). We run from the bgfx root instead, so
    # without this an example that shadows a common header -- 09-hdr, 16-shadowmaps and
    # 21-deferred each ship their own common.sh -- would pick up examples/common/common.sh
    # and fail to find its symbols. Mirrors the shader's own dir in compile_slang().
    cmd = [shaderc, "-f", sc, "--type", stage, "-p", target["profile"], "--platform", target["platform"],
           "-i", os.path.join(root, "examples", ex),
           "-i", os.path.join(root, "examples/common"), "-i", os.path.join(root, "src"),
           "-o", out]
    if os.path.exists(vdef):
        cmd += ["--varyingdef", vdef]
    return run(cmd)

def compile_slang(shaderc, root, slang, stage, out, target):
    # -i dirs so shaderc can preload the *.sh.slang libraries (import bgfx_shader;).
    # The shader's own dir is included too, so a per-example library co-located with the
    # port (e.g. shaders/41-tess/terrain_common.sh.slang) is preloaded -- mirroring how a
    # stock .sc resolves #include "terrain_common.sh" relative to itself.
    # The shader's own dir is included so a per-example library co-located with the port
    # (e.g. shaders/41-tess/terrain_common.sh.slang) is preloaded, mirroring how a stock .sc
    # resolves #include "terrain_common.sh" relative to itself. Order is irrelevant: shaderc
    # preloads *.sh.slang to a dependency fixpoint (see preloadSlangLibraries).
    return run([shaderc, "--lang", "slang", "-f", slang, "--type", stage,
                "-p", target["profile"], "--platform", target["platform"],
                "-i", os.path.dirname(slang),
                "-i", os.path.join(root, "examples/common"), "-i", os.path.join(root, "src"),
                "-o", out])

# ---- test driver ---------------------------------------------------------------
def _norm_uniform(u):
    # u = (name, type, flags, num, reg, regcount, tc, td, tf). For a loose uniform (Vec4/
    # Mat3/Mat4), reg is a byte offset into $Globals -- per-shader and runtime-cosmetic
    # (bgfx binds each uniform by name to its OWN offset), and it varies with where the
    # stock .sc declares the uniform relative to the bgfx_shader.sh include. So it need not
    # match stock. Samplers and storage resources keep reg: there it is the binding. See ADR 0003.
    if u[1] in ("Vec4", "Mat3", "Mat4"):
        return u[:4] + (-1,) + u[5:]
    return u

def _norm_matrix(decos):
    # Drop the struct member index: it tracks the (cosmetic) $Globals layout. What must
    # match is the multiset of RowMajor/ColMajor + MatrixStride decorations -- a transposed
    # matrix still shows up as a RowMajor<->ColMajor difference.
    return sorted((deco, extra) for (_member, deco, extra) in decos)

def compare(ref, got, target="spirv"):
    diffs = []
    for k in ("magic", "ver", "hashIn", "hashOut", "attrs", "size"):
        if ref[k] != got[k]:
            diffs.append(f"{k}: stock={ref[k]} slang={got[k]}")
    # Compare uniforms as a set, ignoring table order and loose-uniform byte offsets (both
    # cosmetic; see _norm_uniform). Identity (name/type/num/regcount/sampler dims), sampler
    # and storage bindings, and the UBO size are all still checked.
    ru = sorted(_norm_uniform(u) for u in ref["uniforms"])
    gu = sorted(_norm_uniform(u) for u in got["uniforms"])
    if ru != gu:
        diffs.append(f"uniforms: stock={ru} slang={gu}")
    # The matrix-layout gate is SPIR-V-only: the Metal envelope's code blob is MSL text,
    # not SPIR-V, so there are no OpMemberDecorate words to compare (both sides parse to
    # []). SPIRV-Cross emits the transpose from the same RowMajor decoration, so the
    # SPIR-V gate already covers Metal's matrix orientation upstream.
    if target == "spirv" and _norm_matrix(ref["matrix"]) != _norm_matrix(got["matrix"]):
        diffs.append(f"matrix-decoration: stock={_norm_matrix(ref['matrix'])} slang={_norm_matrix(got['matrix'])}")
    return diffs

def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--shaderc", default=os.path.join(here, "../../bin/darwin/shaderc"))
    ap.add_argument("--bgfx-root", default=os.path.abspath(os.path.join(here, "../../..")))
    ap.add_argument("--filter", default="")
    ap.add_argument("--target", default="both", choices=["spirv", "metal", "both"],
                    help="which backend target(s) to check (default: both)")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    targets = ["spirv", "metal"] if args.target == "both" else [args.target]
    shaderc = os.path.abspath(args.shaderc)
    root = os.path.abspath(args.bgfx_root)
    shaders_dir = os.path.join(here, "shaders")

    # Each Slang port maps to one or more stock .sc files. A combined port
    # <name>.slang (both entry points) is tested against every stage the example
    # provides; a per-stage port vs_<name>.slang / fs_<name>.slang / cs_<name>.slang
    # (single entry point) is tested against exactly that stock stage. Per-stage
    # files are needed when a shader's VS and FS declare different uniform sets
    # (Slang keeps unused UBO members, which would shift offsets in a combined port).
    prefix_stage = {p: s for s, p in STAGES}
    cases = []  # (ex, stock_base, stage, slang_path)
    for ex in sorted(os.listdir(shaders_dir)):
        exdir = os.path.join(shaders_dir, ex)
        if not os.path.isdir(exdir):
            continue
        for f in sorted(os.listdir(exdir)):
            if not f.endswith(".slang"):
                continue
            stem = os.path.splitext(f)[0]
            path = os.path.join(exdir, f)
            pfx = stem.split("_", 1)[0]
            if pfx in prefix_stage:
                cases.append((ex, stem, prefix_stage[pfx], path))          # per-stage
            else:
                for stage, prefix in STAGES:
                    cases.append((ex, f"{prefix}_{stem}", stage, path))    # combined

    npass = nfail = nskip = 0
    tmp = tempfile.mkdtemp(prefix="slang-compliance-")
    for ex, stock_base, stage, slang in cases:
        sc = os.path.join(root, "examples", ex, f"{stock_base}.sc")
        if not os.path.exists(sc):
            continue
        if args.filter and args.filter not in f"{ex}/{stock_base} [{stage}]":
            nskip += 1
            continue
        for tname in targets:
            target = TARGETS[tname]
            label = f"{ex}/{stock_base} [{stage}] <{tname}>"
            ref_bin = os.path.join(tmp, "ref.bin")
            got_bin = os.path.join(tmp, "got.bin")
            rc1, log1 = compile_stock(shaderc, root, ex, stock_base, stage, ref_bin, target)
            rc2, log2 = compile_slang(shaderc, root, slang, stage, got_bin, target)
            if rc1 != 0:
                print(f"SKIP {label}: stock compile failed\n{log1.strip()}"); nskip += 1; continue
            if rc2 != 0:
                print(f"FAIL {label}: slang compile failed\n{log2.strip()}"); nfail += 1; continue
            is_metal = tname == "metal"
            diffs = compare(parse_envelope(ref_bin, is_metal), parse_envelope(got_bin, is_metal), tname)
            if diffs:
                print(f"FAIL {label}")
                for d in diffs:
                    print(f"       {d}")
                nfail += 1
            else:
                print(f"PASS {label}")
                npass += 1

    print(f"\n{npass} passed, {nfail} failed, {nskip} skipped")
    return 1 if nfail else 0

if __name__ == "__main__":
    sys.exit(main())
