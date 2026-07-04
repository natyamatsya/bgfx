# Slang shader compliance suite

Verifies that the `shaderc` Slang front-end (`--lang slang`) produces output
equivalent to the stock bgfx compiler for the example shaders. This is the
compliance surface for the Slang integration (see `../../../SLANG_ROADMAP.md`).

## Running

```sh
# from the bgfx root, after building tools/bin/<os>/shaderc with Slang support
python3 tools/shaderc/slang-compliance/run.py -v
```

For each `shaders/<example>/<name>.slang`, and each stage the matching example
provides (`examples/<example>/{vs,fs,cs}_<name>.sc`), the runner compiles both
the stock `.sc` and the `.slang` port to SPIR-V envelopes and compares them.

### Two verification gates

1. **Reflection** — magic/version, the inter-stage varying hashes, the uniform
   identity (name, type, num, regcount, sampler/texture info), sampler and storage
   **bindings**, the vertex attribute set, and the constant-buffer **size** must match.
   The uniform table is compared **as a set, ignoring order and loose-uniform byte
   offsets**: both are per-shader details the runtime ignores (each uniform binds by
   name to its own offset), and the offset even varies with where the stock `.sc`
   declares a custom uniform relative to `#include common.sh` — see
   [ADR 0003](../../../docs/adr/0003-slang-auto-provide-predefined-uniforms.md).
2. **SPIR-V matrix decoration** — the `RowMajor`/`ColMajor` + `MatrixStride`
   decorations must match (compared as a multiset, minus the layout-dependent member
   index). Reflection does **not** reveal a transposed matrix, so this second gate is
   required (the Slang session is set to column-major, which maps to SPIR-V RowMajor
   to match bgfx — see `shaderc_slang.cpp`).

The code blob itself is intentionally not compared — it legitimately differs
between glslang and Slang.

## Porting patterns (bgfx `.sc` → Slang)

| bgfx `.sc` | Slang |
|---|---|
| `$input a_position, a_color0` / `varying.def.sc` | a `struct` with `POSITION`, `COLOR0`, `TEXCOORDn` semantics; field names `a_position` etc. |
| `$output v_color0` | a `V2F` struct field with the interpolant semantic; keep the `v_*` field name (drives the varying hash) |
| `gl_Position` | `float4 pos : SV_Position` |
| `gl_FragColor` / `gl_FragData[0]` | fragment return `: SV_Target` |
| `uniform vec4 u_foo;` (custom) | a loose global `float4 u_foo;` **declared in the shader** (see below) |
| predefined uniforms (`u_modelViewProj`, …) | **just use them** — `shaderc` auto-declares the referenced ones in bgfx's canonical order ([ADR 0003](../../../docs/adr/0003-slang-auto-provide-predefined-uniforms.md)); `--slang-no-predefined` opts out. |
| `mul(u_model[0], v)` | `mul(u_model, v)` — `u_model` is auto-provided as a single matrix; multi-bone `u_model[1..]` must be declared by hand. |
| `mul(u_modelViewProj, v)` | `mul(u_modelViewProj, v)` — order unchanged (matrix layout handled by the compiler) |
| `SAMPLER2D(s_tex, 0)` + `texture2D(s_tex, uv)` | `import bgfx_shader;` then the library's sampler abstraction (bgfx N/N+16 binding convention) — TODO |
| `NUM_THREADS(x,y,z)` | `[numthreads(x,y,z)]` on the compute entry point (TODO) |
| `IMAGE2D_*` / `BUFFER_*` | `RWTexture2D` / `(RW)StructuredBuffer` (TODO) |

A single `.slang` file may hold multiple entry points (`[shader("vertex")]`,
`[shader("fragment")]`, `[shader("compute")]`); the runner selects the one whose
stage matches `--type`.

### Predefined uniforms are auto-provided; custom uniforms are declared; the library holds samplers + helpers

- **Predefined uniforms are auto-declared by `shaderc`** in bgfx's canonical order, so shaders just use
  `u_modelViewProj` etc. ([ADR 0003](../../../docs/adr/0003-slang-auto-provide-predefined-uniforms.md)).
  Only referenced ones are injected — Slang binds parameters *before* dead-code elimination (for layout
  stability, by design), so a blanket declaration of all predefined uniforms would bloat every envelope.
  `--slang-no-predefined` disables this and reverts to the manual model of [ADR 0002](../../../docs/adr/0002-slang-shader-library-composition.md).
- **Custom uniforms are declared in the shader** (a loose global `float4 u_foo;`), only the ones it uses —
  read directly off the source `.sc`.
- **The shared library `bgfx_shader.sh.slang` (+ `shaderlib.sh.slang`, `bgfx_compute.sh.slang`) holds the
  sampler abstraction, types, and helper *functions*** — Slang dead-strips unused functions/types
  correctly, so importing the library does not bloat the envelope. Shaders write `import bgfx_shader;`;
  `shaderc_slang.cpp` preloads each `*.sh.slang` in the include dirs as a module named after the file
  (minus `.sh.slang`). Library symbols are `public` (uniforms, if any, `public uniform`).

## Coverage matrix (in progress)

| Feature class | Representative example | Status |
|---|---|---|
| plain VS/FS + uniform | 01-cubes | ✅ passing |
| auto-provided predefined uniforms (per-stage) | 04-mesh, 03-raymarch | ✅ passing |
| auto-provided `u_model` (single matrix) | 02-metaballs | ✅ passing |
| single texture | 13-stencil (`stencil_texture`) | ✅ passing |
| multi-texture | 19-oit (`oit_wb_blit`) | ✅ passing |
| shadow / compare sampler | 31-rsm (`rsm_combine`) | ✅ passing |
| cubemap sampler | 09-hdr (`hdr_skybox`) | ✅ passing |
| explicit LOD (`texture2DLod`) | 08-update (`update_mip`) | ✅ passing |
| texelFetch (`Texture.Load`) | 51-gpufont (`slug`) | ✅ passing |
| instancing (`i_data`) | 05-instancing | ✅ passing |
| compute + storage buffer | 39-assao (`cs_assao_load_counter_clear`) | ✅ passing |
| compute + storage image | 37-gpudrivenrendering (`cs_gdr_copy_z`) | ✅ passing |

The remaining ~300 example shaders are mostly repeats of these patterns; the
matrix above establishes coverage before scaling to the long tail.

## Debugging: `refl_dump`

When the runner reports an envelope mismatch, `refl_dump.cpp` prints the Slang
reflection structure of a shader exactly as `shaderc_slang.cpp` sees it (same
target, matrix layout, and `-fvk-*-shift` bind shifts), plus the SPIR-V bindings.
Build/run instructions are in the file header; it needs `libslang` and its
companion dylibs on the loader path (e.g. a Slang release `lib/` dir).

```sh
DYLD_LIBRARY_PATH=/path/to/slang/lib ./refl_dump <shader.slang> <entryPoint> <vertex|fragment|compute>
```

Binding convention reproduced by `shaderc_slang.cpp` (see `src/shader.h`):
UBO at binding 0 (vertex) / 1 (fragment), textures `+kSpirvBindShift`, samplers
`+kSpirvBindShift+kSpirvSamplerShift`, images/RW buffers `+kSpirvBindShift`. Since
all resources shift to bindings ≥ 2, the UBO is the only thing that can sit at
binding 0/1 — which is how the live-uniform gate detects an unused constant buffer.
