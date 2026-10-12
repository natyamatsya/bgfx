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

## Targets

`--target` selects the backend the two sides are compiled through. `both` (the default)
means `spirv` + `metal`, which is what the macOS CI job runs. `dxil` has to be asked for
explicitly: it needs a Windows host, because Slang's DXIL backend goes through
`libdxcompiler`. Profiles mirror `scripts/shader.mk` -- graphics at `s_6_0`, compute at
`s_6_5` -- so the suite drives the same route the shipped blobs are built through.

Three envelope fields are normalised on DXIL, because the D3D12 runtime parses but never
consumes them: `renderer_d3d12.cpp` reads `num` and `texFormat` only to feed a `BX_TRACE`
(`texComponent` is `BX_UNUSED` outright), and the sampler branch uses `regIndex` and
`texDimension` alone -- a sampler's `regCount` is never read, unlike a user uniform's,
which reaches `writeUniformHandle`. Stock and Slang disagree on all three (stock `num=0`
against Slang's `1`; stock `regCount=1`/`texFormat=0` for a sampled texture against
Slang's `0`/`41`, i.e. `TextureFormat::Count`). Every field the backend acts on is still
compared.

### DXIL: matching the stock HLSL front-end

All 302 cases pass on `dxil` as of Slang 2026.19. Getting there meant separating two kinds
of difference, because the Slang front-end emits one reflection for every target while the
stock front-ends do not agree with each other.

Four were the Slang path's to fix, and were fixed in `shaderc_slang.cpp` the way the
earlier `shaderc/metal` and `vk/mtl` reflection fixes were -- a target-specific branch that
follows the stock convention for that target:

| | divergence | fix |
|---|---|---|
| A | unmapped vertex inputs emitted as `UINT16_MAX` | The GLSL and Metal front-ends emit a placeholder for every input that is not a bgfx attribute (instance data on TEXCOORD semantics, `SV_InstanceID`); the HLSL one emits only real attributes. `collectAttributes` now follows the target. The runtime discards an unmapped id either way, so this is convention, not behaviour. |
| B | dead globals kept | The SPIR-V path strips a global by looking for its binding in the generated SPIR-V, which DXIL has no equivalent of, so the envelope kept everything. Now asks the compiler: `IMetadata::isParameterLocationUsed`. It was rejected for the Vulkan path because `-fvk-*-shift` moves a binding out from under the reflection, and that does not apply here -- DXIL applies no shift. A failed query counts as live. |
| C | storage images and buffers in the uniform table | Listed on SPIR-V/Metal, omitted by stock HLSL. D3D12 binds a UAV from the bgfx binding slot, and the entry was typed `End` with no sampler bit, so the runtime took each for a user uniform and warned it could not find it. Omitted on DXIL. |
| D | `kUniformCompareBit` on shadow samplers | A SPIR-V/Metal convention; stock HLSL never sets it and the D3D12 sampler branch never reads it. Not set on DXIL. |

The rest are the stock front-ends disagreeing with each other, so no change to the Slang path
could satisfy both targets. These are reconciled in `compare()`, each with the measurement
that pins it:

- **Unused cbuffer members and array tails.** DXC strips an individually-unused cbuffer
  member; glslang does not, and neither does Slang.
  `16-shadowmaps/fs_shadowmaps_color_lighting_esm` is 208 bytes over 14 uniforms on `spirv`
  for *both* front-ends, and on `dxil` is 192 over 13 for stock against Slang's 208 over 14.
  208 is the honest size of the Slang shader's cbuffer and shaderc must report it: bgfx
  uploads `size` bytes from offset 0, so under-reporting would truncate a live uniform
  sitting above a stripped one. B cannot close this -- `isParameterLocationUsed` is
  register-granular and these members share one `b#`. The same split hits array extents:
  `examples/09-hdr/common.sh` declares `u_offset[16]` and uses 9, which glslang trims to 9
  and DXC keeps at 16, so a port that matches one target cannot match the other (verified by
  declaring `[16]` in the port: `dxil` then matches exactly and `spirv` breaks). So on DXIL
  `size` and `regCount` are not compared, and stock's uniforms must be a *subset* of
  Slang's -- which keeps the direction that matters, since a uniform stock has and Slang
  lacks is one bgfx will not bind.
- **A sampler name ending in "Sampler".** `SAMPLER2D(u_DmapSampler, 0)` declares the texture
  as `u_DmapSampler`, and the stock HLSL reflection strips a trailing `Sampler`, which
  over-fires and reports `u_Dmap` (41-tess). The comparison applies the same strip to both
  sides. D3D12 never looks a sampler up by name, so neither spelling reaches the backend.
- **`texDimension` stock cannot determine.** Stock reports 0 for textures Slang correctly
  types as 2D (27-terrain, 41-tess, 46-fsr's gather/load paths). The backend does read this
  field, so it is compared wherever stock knows the answer and waived only for the sampler
  and register where stock has none to give.

Fixing A-D changed the DXIL envelopes the tree ships, so the committed DXIL blobs were
regenerated and `rt_smoke`, `rt_pipeline_smoke`, `rt_pipeline_p0_referee` and
`rt_pipeline_cornellbox` re-run on the 4090 and on WARP.
