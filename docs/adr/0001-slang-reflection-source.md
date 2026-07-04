# 1. Reflection source for Slang integration: dlsym'd Slang C reflection API

- **Status:** Accepted
- **Date:** 2026-07-04
- **Context branch:** `experimental/research-slang-support`
- **Related:** [`SLANG_ROADMAP.md`](../../SLANG_ROADMAP.md) (overall Slang integration plan)

## Context

We are adding [Slang](https://github.com/shader-slang/slang) as an input shader language to `shaderc`
(see the roadmap for the full plan). The integration follows bgfx's existing **DXC precedent**: Slang is
consumed as a **prebuilt shared library loaded dynamically at runtime** (`bx::dlopen` +
`bx::dlsym`, gated by `SHADERC_CONFIG_HAS_SLANG`), *not* vendored as source and *not* statically linked
(`tools/shaderc/shaderc_dxil.cpp:150-219` is the template). This keeps the backend optional and avoids
ODR collisions with bgfx's own glslang/spirv-tools that Slang bundles.

To write bgfx's compiled-shader binary "envelope", `shaderc` needs **reflection**: per-uniform
name/type/array-count/register-offset, texture/sampler bindings, and vertex-input attributes.

A de-risk smoke test surfaced a constraint that shaped this decision:

- Slang's **compile** API (`IGlobalSession`, `ISession`, `IModule`, `IComponentType`) is pure-virtual
  COM. It works through the vtable with a **single** dlsym'd entry point (`slang_createGlobalSession`),
  and produces valid SPIR-V — confirmed working with a compiler-only `libslang` (no companion libs).
- Slang's **reflection** classes (`slang::ProgramLayout`, `TypeLayoutReflection`, …) are **inline C++
  wrappers over a C API** (`spReflection_*`). Those C symbols must be resolved at **link time** — so a
  pure-`dlopen` build cannot use the C++ reflection wrappers directly (the smoke test compiled but
  failed to link on `spReflection_*`).

Additionally, **hardware raytracing** is a desired later stage, which raises the question of which
reflection source is more future-ready.

## Decision

Obtain reflection by **`dlsym`'ing the `spReflection_*` C API** and calling it directly (deriving the
function-pointer signatures from the inline wrappers in `slang.h`, since `slang::ProgramLayout*` casts
to the C `SlangReflection*` handle). Compilation continues to use the COM vtable via the single
`slang_createGlobalSession` entry point.

This keeps `libslang` a **pure `dlopen` dependency** while using **Slang's own authoritative
reflection** to populate the bgfx envelope.

## Consequences

### Positive
- **Pure `dlopen` preserved.** `libslang` stays optional and loaded at runtime, matching the DXC
  precedent — the best posture for upstreaming (`shaderc` still builds and runs without Slang present).
- **Authoritative reflection.** Slang reports the intended layout (std140 offsets, array sizes,
  semantics, predefined-by-name uniforms) rather than what a downstream tool infers from emitted SPIR-V.
- **Raytracing-ready (the deciding factor for the future roadmap).** RT is fundamentally a
  front-end-knowledge problem, and Slang's reflection is where that knowledge lives:
  - Entry points are classified by RT stage (`SLANG_STAGE_RAY_GENERATION`, `…_MISS`,
    `…_CLOSEST_HIT`, `…_ANY_HIT`, `…_INTERSECTION`, `…_CALLABLE`) via `EntryPointReflection::getStage()`
    — required to build the shader binding table.
  - Slang models RT-specific constructs with no raster analogue: **acceleration structures** (first-class
    resource shape), **ray payloads**, **hit attributes**, and **shader-record / SBT buffers**.
  - For RT the codegen path is Slang → SPIR-V **directly** (Vulkan), where SPIRV-Cross is not in the loop
    at all — so anchoring reflection on Slang avoids depending on the weakest link for the RT feature.
  - The stable **C reflection API** is what we bind to (not Slang's reflection-*JSON*, which upstream
    flags as in-flux).

### Negative / costs
- **Boilerplate.** ~15–25 `spReflection_*` C functions must be hand-declared as dlsym'd function
  pointers in `shaderc_slang.cpp` and kept in sync with the vendored Slang version.
- **Table grows with features.** Adding RT (or other) reflection later means extending the dlsym'd
  table with the corresponding accessors — an incremental change, but a real one.
- **Signature provenance.** The function-pointer typedefs are derived from `slang.h`'s inline wrappers
  and are pinned to the vendored Slang release (`3rdparty/slang/README.md` records the tag).

## Alternatives considered

### A. Reflect Slang's SPIR-V with SPIRV-Cross (rejected)
Keep `libslang` a one-symbol SPIR-V generator and reflect the generated SPIR-V with bgfx's
already-linked SPIRV-Cross (which `shaderc` already uses for texture reflection). **Maximized code
reuse and minimized the libslang surface**, and Slang's SPIR-V preserves the names bgfx matches on
(`u_modelViewProj`, `a_position`, …). Rejected because it is the **weaker path for raytracing** —
SPIRV-Cross is a raster/compute cross-compiler whose RT reflection (acceleration structures, payloads,
SBT records) and RT cross-compilation are comparatively immature — and it discards Slang's authoritative
layout information.

### B. Dynamically link `libslang` (rejected)
Use `slang.h`'s reflection wrappers directly with the least code. Rejected because `shaderc` would gain
a **hard load-time dependency** on `libslang.dylib` (it would not start if the library were absent),
which breaks the optional-backend posture that the DXC `dlopen` precedent deliberately chose, and is the
least upstreamable option.

## Notes

This ADR records only the *reflection source*. The broader "integrate Slang via dynamically-loaded
`libslang`", "chain Slang → SPIR-V → SPIRV-Cross for backend parity", and "SPIR-V/Vulkan vertical slice
first" decisions are documented in `SLANG_ROADMAP.md`; if we adopt ADRs more widely, those should be
back-filled as their own records.
