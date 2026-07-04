# bgfx × Slang — Shader Language Support Roadmap

> Status: **Phase 1 (SPIR-V/Vulkan vertical slice) implemented and verified.** Branch: `experimental/research-slang-support`.
> This document is the durable record of the plan to add [Slang](https://github.com/shader-slang/slang)
> as an input shader language to bgfx's `shaderc` tool. It is written to be idiomatic to bgfx so the work
> has a realistic chance of being **upstreamed**.

## Progress

- ✅ **Phase 0 — local build fixed.** Root cause was the archiver: `make` used Homebrew GNU `ar`,
  whose non-8-byte-aligned archive members Apple's newer `ld` rejects. Building with `AR=/usr/bin/ar`
  links cleanly; no Xcode/compiler change was needed.
- ✅ **Phase 1 — SPIR-V/Vulkan vertical slice.** A `.slang` port of `examples/01-cubes` compiles through
  `shaderc` into a v11 Vulkan envelope whose **reflection is byte-identical to the stock bgfx compiler**
  for both stages (uniform `u_modelViewProj` Mat4/regIndex 0/regCount 4; Position+Color0 attributes;
  cbuffer size; VS `hashOut` == FS `hashIn`). The FS correctly strips the unused `u_modelViewProj`.
- **Key implementation findings** (fed back into the plan below):
  - Slang's compile API is pure-`dlopen`-clean (one factory symbol, COM vtable), but its C++ reflection
    wrappers forward to a C API that needs link-time symbols — resolved by dlsym'ing that C API. See
    [ADR 0001](docs/adr/0001-slang-reflection-source.md).
  - Unused-uniform stripping (to match glslang's live-uniform reflection) uses
    `IMetadata::isParameterLocationUsed` (a virtual — no extra dlsym).
  - The macOS `libslang-compiler` dylib depends only on `libc++`/`libSystem`; the 107 MB LLVM and the
    glslang companions are not needed for the direct-SPIR-V path, so only `libslang.dylib` (~28.7 MB) is
    vendored. Pinned release: **v2026.12.2**.
- **Not yet done:** live-render verification under a real Vulkan renderer (needs a VK host / MoltenVK —
  the plan's secondary gate); backend fan-out (Phase 2).

## 1. Goal

Let users author shaders in **Slang** — a modern shading language with modules, generics, and strong
tooling — while:

1. **Staying idiomatic to bgfx's architecture and style**, so the changes are upstreamable.
2. **Not losing Slang's tooling.** We drive Slang's compiler + reflection API and rewrite its output into
   bgfx's existing compiled-shader binary format, rather than reimplementing shader translation.

The end state: a `.slang` shader compiles through `shaderc` into the **identical** binary "envelope"
bgfx's runtime already consumes, for every existing backend — with **zero runtime changes**.

## 2. How bgfx compiles shaders today (baseline)

bgfx authors shaders in a bgfx-flavored GLSL dialect (`*.sc` + `varying.def.sc`), then:

```
.sc source ──▶ fcpp preprocessor + bgfx_shader.sh/bgfx_compute.sh macros
           ──▶ glslang ──▶ SPIR-V
           ──▶ per-target backend:  SPIRV-Cross (Metal/GLSL/ESSL) │ tint (WGSL) │ DXC/fxc (DXIL/HLSL)
           ──▶ bgfx binary "envelope" (reflection + target code)  ──▶ runtime loads it
```

Reflection today comes from **glslang** (uniform offsets, array sizes, types), **SPIRV-Cross**
`get_shader_resources()` (textures/samplers/buffers + binding indices), and **glslang live-attributes**
(vertex inputs) — see `tools/shaderc/shaderc_spirv.cpp:658-880`.

## 3. Guiding decisions (locked)

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Dependency = DXC-style dynamic load** of a prebuilt `libslang`. Not vendored source, not static-linked. | Mirrors bgfx's existing DXC precedent; avoids ODR collisions with bgfx's own glslang/spirv-tools that Slang bundles; keeps genie build untouched. |
| 2 | **Chaining = Slang → SPIR-V → SPIRV-Cross** for Metal/GLSL/ESSL. Reflection from Slang's `getLayout()` API. | Reuses bgfx's battle-tested backends; Slang's direct GLSL is explicitly low-maturity and its Metal is newer than SPIRV-Cross. Slang cleanly replaces only the front-end + SPIR-V generation. |
| 3 | **Scope = SPIR-V/Vulkan vertical slice first**, then fan out. | Proves the reflection→envelope mapping end-to-end at lowest risk before widening surface. |

### Why dynamic-load `libslang` is the idiomatic choice
bgfx uses two dependency patterns: (a) **vendored source built by genie** (glslang, spirv-cross,
spirv-tools, fcpp, glsl-optimizer, tint); and (b) **prebuilt shared library loaded at runtime** — which is
exactly how bgfx already handles the giant DXC compiler: `tools/bin/{windows,linux}/dxcompiler.{dll,so}`
loaded via `bx::dlopen` + `bx::dlsym("DxcCreateInstance")` (`tools/shaderc/shaderc_dxil.cpp:150-219`),
gated by `SHADERC_CONFIG_HAS_DXC`. Slang is the same shape as DXC (large, LLVM-adjacent, its own
CMake+Python build, bundles its own glslang/spirv-tools), so it follows pattern (b). Its one C-ABI entry
point, `slang_createGlobalSession`, is `dlsym`-friendly; the rest of the COM-style API is used through the
vendored `slang.h` headers. (Aside: DXC's darwin dll name is a placeholder `"dxcompiler???"` — a vendored
`libslang.dylib` actually gives Slang a *better* macOS story than DXC has.)

## 4. The binary "envelope" — the frozen contract

`BGFX_SHADER_BIN_VERSION 11`. Any Slang front-end must reproduce this **byte-for-byte**. Header written by
the dispatcher (`tools/shaderc/shaderc.cpp:2403-2420`); body + trailer by each backend (canonical writer
`writeUniformArray`, `tools/shaderc/shaderc_spirv.cpp:337-377`; SPIR-V trailer `:858-882`). Runtime read
side: shared `src/bgfx_p.h:5240-5326`, then per-renderer trailer (Vulkan `src/renderer_vk.cpp:5510-5773`).

```
magic:u32   ('V'|'F'|'C', 'S','H', version=11)
hashIn:u32                                   # 0 for VSH/CSH
hashOut:u32                                  # 0 for FSH
count:u16                                    # uniform records
  per uniform:
    nameSize:u8, name[nameSize]              # NOT NUL-terminated
    type:u8 (| kUniform*Bit flags)           # Sampler/End/Vec4/Mat3/Mat4 + fragment/sampler/readonly/compare
    num:u8                                    # array size
    regIndex:u16                              # cbuffer byte offset OR binding index
    regCount:u16                              # vec4-register count OR descriptor-type id
    texComponent:u8, texDimension:u8, texFormat:u16
shaderSize:u32, code[shaderSize], nul:u8     # code = SPIR-V words (VK) / MSL text (Metal) / GLSL text (GL) / DXBC|DXIL (D3D)
numAttr:u8, attrId:u16 × numAttr             # vertex shaders only
size:u16                                     # total constant-buffer bytes
```

**bgfx-specific conventions the front-end must reproduce (Vulkan/SPIR-V):**
- Texture image binding `N` ↔ its sampler at `N+16`, plus a `+2` UBO binding shift
  (`src/shader.h:13-16`, `tools/shaderc/shaderc_spirv.cpp:780`, runtime `src/renderer_vk.cpp:5627-5668`).
- **Predefined uniforms** (`u_modelViewProj`, `u_view`, `u_viewRect`, …) are recognized purely by **name**
  at load time (`src/bgfx.cpp:1245-1278`, `nameToPredefinedUniformEnum`). The `.slang` source must name them
  literally.
- Vertex attribute ids via `bgfx::attribToId` (`src/vertexlayout.cpp:213`); only vertex shaders carry the
  attribute table.
- Inter-stage `hashIn`/`hashOut` link a VS's outputs to an FS's inputs; computed by `parseInOut`'s
  sort + `HashMurmur2A` over varying names (`tools/shaderc/shaderc.cpp:1075-1113`).

## 5. Implementation roadmap

### Phase 0 — Fix the local build (prerequisite, macOS dev host) ✅ done
The current `make shaderc` compiles fully but **fails at link** with
`ld: ... 64-bit mach-o not 8-byte aligned` across every `.a`. Root cause: the generated makefile uses
`AR = ar` (`.build/projects/gmake-osx-arm64/shaderc.make:37`), which resolves to **Homebrew GNU ar 2.46.1**
(`/opt/homebrew/opt/binutils/bin/ar`, ahead of `/usr/bin/ar`). GNU ar does not 8-byte-pad archive members;
Apple's newer `ld` (Xcode 27 Beta 2) rejects them. (Proof: Apple `ar` → 528 B vs GNU `ar` → 508 B for the
same object.)

Fix (fast — reuses compiled `.o`, only re-archives):
```sh
rm -f .build/osx-arm64/bin/*.a
make shaderc AR=/usr/bin/ar
```
Alternative: prepend `/usr/bin` to `PATH`, and/or `sudo xcode-select -s /Applications/Xcode-26.5.0.app`
(stable Xcode 16.4 / 26.5 are installed) before building.

### Phase 1 — SPIR-V / Vulkan vertical slice ✅ done (reflection byte-verified vs stock)
Deliver one `.slang` shader compiling end-to-end into a v11 Vulkan envelope the runtime renders.

**1a. Vendor the dependency (headers + prebuilt lib only)**
- `3rdparty/slang/include/` ← Slang public headers only (`slang.h`, `slang-com-ptr.h`,
  `slang-com-helper.h`, and transitive includes; header-only). Add `3rdparty/slang/LICENSE` (Apache-2.0
  WITH LLVM-exception) + a `README.md` pinning the exact upstream tag.
- `tools/bin/<os>/` ← prebuilt `libslang.dylib` / `libslang.so` / `slang.dll` from the matching release
  (`otool -L` / `ldd` to catch and bundle companion libs).
- `tools/shaderc/shaderc.h`: add `SHADERC_CONFIG_HAS_SLANG` via `__has_include(<slang.h>)` (mirror the
  `SHADERC_CONFIG_HAS_TINT` block at `:46-52`), and declare `bool compileSlangShader(const Options&,
  uint32_t, const std::string&, bx::WriterI*, bx::WriterI*)` beside `compileSPIRVShader` (`:184`).
- `scripts/shaderc.lua`: add `path.join(BGFX_DIR, "3rdparty/slang/include")` to `includedirs{}`
  (`:709-730`). **No `links{}` change, no genie StaticLib project** — the whole point of dynamic load.

**1b. New `tools/shaderc/shaderc_slang.cpp`** (auto-globbed by `tools/shaderc/**.cpp`)
- Wrap in `#if SHADERC_CONFIG_HAS_SLANG … #else`(stub returns false)`… #endif`.
- **Runtime load**, mirroring `shaderc_dxil.cpp:150-219`: `bx::FilePath(bx::Dir::Executable).getPath()
  .join("libslang.dylib"|…)` → `bx::dlopen` → `bx::dlsym<PFN>(dll, "slang_createGlobalSession")` → call
  with `SLANG_API_VERSION`; matching `unload()`.
- **Compile flow**: `createSession(TargetDesc{format=SLANG_SPIRV, profile=findProfile("spirv_1_5")})`
  with binding-shift options (Risk 1) → `loadModuleFromSourceString` → `findEntryPointByName` (stage from
  `Options.shaderType`) → `createCompositeComponentType` → `link` → `getEntryPointCode(0,0,…)` (SPIR-V) +
  `getLayout(0,…)` (reflection) + `getEntryPointMetadata` (unused-param stripping).
- `compileSlangShader` writes the **entire** envelope (header + body + trailer) — the hashes need
  reflection, so the Slang dispatch branch is a one-liner.

**1c. Reflection → envelope mapping (the crux)** — walk `slang::ProgramLayout` to fill `UniformArray` +
attribute ids, reproducing today's glslang+SPIRV-Cross output:
- *Uniforms* (`getGlobalParamsVarLayout()` → ConstantBuffer element struct fields): `name=getName()`,
  `regIndex=getOffset(UNIFORM)` (bytes), kind → `{Vec4:regCount=num, Mat3:num*3, Mat4:num*4}`
  (reproduces `shaderc_spirv.cpp:673-702`).
- *Textures/samplers*: `type=Sampler|kUniformSamplerBit(|kUniformCompareBit)`, `regIndex=binding`,
  `regCount=0`; fill `texComponent/texDimension/texFormat` via existing
  `textureComponentTypeToId`/`textureDimensionToId`/`s_textureFormats[]`. Detect compare via the paired
  sampler at `binding+16` (mirrors `:778-786`).
- *Vertex attributes* (vertex entry-point `VaryingInput` leaves): `getSemanticName()/getSemanticIndex()`
  → `Attrib::Enum` → `attribToId` (reuse the DXIL semantic table `shaderc_dxil.cpp:222+`).
- *Varying hashes*: reproduce `parseInOut`'s sort + `HashMurmur2A` over VS `VaryingOutput` / FS
  `VaryingInput` leaf field names (exclude `SV_Position`) so VS↔FS link.
- *Reuse over copy*: factor `writeUniformArray` + trailer + texture/attrib helpers out of the anonymous
  `spirv` TU into a shared `shaderc_spirv.h` so both files share one byte-layout source. Propose in the PR;
  fall back to a ~50-line copy if the maintainer prefers self-contained backend files. **Never** re-derive
  the byte order independently.

**1d. CLI / dispatch wiring**
- `Options.sourceLang` (`enum { BgfxSc, Slang }`) in `shaderc.h:135-170`, defaulted + dumped.
- `--lang <bgfx|slang>` + `.slang`-extension auto-detect near `shaderc.cpp:2888-2917`; add to `help()`.
- Skip the mandatory `varying.def.sc` read for Slang (`shaderc.cpp:3027-3041`).
- Early branch at inner `compileShader` `:1241` (after profile lookup, before `Preprocessor`):
  `if Slang → return compileSlangShader(...)`. Existing SpirV dispatch sites (`:1749/1914/2806`) untouched.

### Phase 2+ — Backend fan-out
Same Slang → SPIR-V front-end; only the SPIR-V→target step changes, per `profile->lang`:
- **Metal**: SPIR-V → existing SPIRV-Cross MSL path; compute needs the `3×u16` threadgroup-dims trailer
  (`EntryPointReflection::getComputeThreadGroupSize`).
- **GL / ESSL**: SPIR-V → SPIRV-Cross GLSL text.
- **D3D (DXBC/DXIL)**: SPIR-V → SPIRV-Cross HLSL → existing `compileHLSLShader`/`compileDxilShader`.
- **WGSL**: SPIR-V → tint (`compileWgslShader`).

Recommended refactor once ≥2 targets exist: have `compileSlangShader` yield `(spirv, ProgramLayout)` to a
shared `emitEnvelopeFromSpirv(lang, …)` that the current backends grow into. Keep Phase 1 direct.

## 6. Verification

1. **Build** (after Phase 0 fix): rebuild shaderc with `3rdparty/slang` present; `shaderc --help` shows `--lang`.
2. **Author** `cubes.slang` (port of `examples/01-cubes`): `[shader("vertex")] vertexMain` /
   `[shader("fragment")] fragmentMain`, naming `u_modelViewProj`, `a_position:POSITION`, `a_color0:COLOR0`,
   `v_color0`.
3. **Compile**: `shaderc --lang slang -f cubes.slang --type vertex -p spirv -o vs_cubes.bin` (+ fragment).
4. **Byte-golden compare (primary CI gate, no GPU):** compile stock `vs_cubes.sc` with stock shaderc
   `-p spirv` as reference; parse both envelopes and assert equality per the field order in
   `bgfx_p.h:5287-5326` / `renderer_vk.cpp:5554-5773` — magic `VSH\x0b`, uniform
   `u_modelViewProj/Mat4/regIndex0/regCount4`, `numAttr==2`, VS `hashOut == FS hashIn`.
5. **Live render:** load the `.bin`s in 01-cubes under **Vulkan**. Host caveat: dev host is osx-arm64
   (default Metal) — use MoltenVK (bgfx VK over MoltenVK on Apple Silicon), a Linux/Windows VK host, or a
   SwiftShader ICD for headless CI. Byte-compare (4) is the gate; live-render (5) needs a VK host.

## 7. Risks

| # | Risk | Mitigation |
|---|------|------------|
| 1 | **Binding N/N+16 (highest).** bgfx's texture=N / sampler=N+16 + `+2` UBO shift is a hard runtime contract. | Confirm Slang's `-fvk-{t,s,b}-shift` options emit exactly these decorations with the *direct*-SPIR-V backend; `spirv-dis` a two-texture shader **first**. Fallback: explicit `[[vk::binding]]` in source, or a SPIRV-Cross decoration rewrite. |
| 2 | **Varying-hash parity.** VS `outputHash` must byte-equal FS `inputHash` or draws silently fail to bind. | Reproduce leaf enumeration + sort + murmur exactly; dedicated unit test on a VS/FS pair. |
| 3 | **Unused-uniform stripping.** Slang reflects *declared* params; bgfx strips *used*-only today (`shaderc_spirv.cpp:640-655`). | Use `IMetadata::isParameterLocationUsed` so the envelope's uniform table matches the SPIR-V. |
| 4 | **License / committed binary.** Apache-2.0 + a committed `.dylib/.so/.dll` is a maintainer call. | Include Apache LICENSE/NOTICE under `3rdparty/slang/`; PR states the no-static-link posture (same model bgfx tolerates for DXC). Fallback: headers-only + "bring-your-own libslang next to shaderc" (the `__has_include` guard already makes the backend optional). |
| 5 | **Version pinning.** `SLANG_API_VERSION` mismatch fails `slang_createGlobalSession`. | Pin the header + prebuilt lib to the same Slang release tag in `3rdparty/slang/README.md`. |

## 8. Upstreaming notes

- The whole backend is optional behind `SHADERC_CONFIG_HAS_SLANG` — a build without `3rdparty/slang` is
  unaffected. This mirrors how `SHADERC_CONFIG_HAS_DXC`/`_HAS_TINT`/`_HAS_GLSLANG` gate their backends.
- Zero runtime changes: the envelope is unchanged, so `src/` is read-only reference in this work.
- Input-language selection (`--lang`) is orthogonal to target selection (`--profile`), matching how the
  tree already separates stage (`--type`) from target (`--profile`).

## 9. Key files

| File | Role |
|------|------|
| `tools/shaderc/shaderc_slang.cpp` | **new** — dlopen + Slang compile + reflection→envelope |
| `tools/shaderc/shaderc.cpp` | `Options.sourceLang`, `--lang`/ext detect (`:2888`), Slang branch (`:1241`), skip varying.def (`:3027`) |
| `tools/shaderc/shaderc_spirv.cpp` | source of `writeUniformArray` (`:337`) + trailer (`:858-882`) + helpers to share |
| `tools/shaderc/shaderc.h` | `SHADERC_CONFIG_HAS_SLANG` guard, `Options`, `compileSlangShader` decl |
| `scripts/shaderc.lua` | one `includedirs` line |
| `tools/shaderc/shaderc_dxil.cpp:150-219` | read-only template for the dynamic-load pattern |
| `src/shader.h`, `src/bgfx_p.h`, `src/renderer_vk.cpp`, `src/bgfx.cpp` | read-only envelope contract (match, don't edit) |
