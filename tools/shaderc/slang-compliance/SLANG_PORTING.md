# Porting bgfx example shaders to Slang

This suite holds faithful **1-to-1** Slang ports of the bgfx example shaders. A port is a
straight translation of the real `.sc` algorithm — **no stubs, no elision** — that also
produces a byte-compatible reflection *envelope*. The runner (`run.py`) compiles both the
stock `.sc` and the `.slang` port to SPIR-V and compares the **reflection envelope**
(uniforms, sampler/buffer bindings, vertex attributes, varying hashes, UBO size, matrix
layout) — **not** the compiled code (glslang and Slang legitimately emit different SPIR-V).
So the interface must match stock exactly while the body stays a faithful translation.

Ports live in `shaders/<example>/`; the runner discovers them automatically.

## Translation rules (the math stays verbatim; only the shell changes)

| bgfx `.sc` (GLSL dialect) | Slang |
|---|---|
| `$input a_… ` / `$output v_…` (from `varying.def.sc`) | a `struct` for VS input (attributes) and a `struct` for varyings (V2F) |
| attribute/varying semantics | `a_position:POSITION`, `a_normal:NORMAL`, `a_tangent:TANGENT`, `a_color0:COLOR0`, `a_texcoord0:TEXCOORD0`, `v_*:TEXCOORDn`/`COLORn`/`NORMAL`/`BINORMAL` |
| `void main()` | `[shader("vertex")] V2F vertexMain(VSInput input)` / `[shader("fragment")] float4 fragmentMain(V2F input) : SV_Target` / `[shader("compute")] [numthreads(x,y,z)] void computeMain(uint3 dtid : SV_DispatchThreadID, …)` |
| `gl_Position` | VS output field `float4 pos : SV_Position` |
| `gl_FragColor` / `gl_FragData[0]` | FS return value (`: SV_Target`) |
| `gl_FragData[0..n]` (MRT) | return a `struct` of `float4 targetN : SV_TargetN` |
| `gl_FragDepth` | output field `float depth : SV_Depth` |
| `gl_FragCoord` | input field `float4 … : SV_Position` |
| `SAMPLER2D(s_tex, N)` | `Texture2D s_tex : register(tN); SamplerState s_texSampler : register(sN);` (also `SAMPLERCUBE`→`TextureCube`, `SAMPLER2DARRAY`→`Texture2DArray`) |
| `texture2D(s_tex, uv)` | `texture2D(s_tex, s_texSampler, uv)` — add the paired `<name>Sampler` (same for `texture2DLod`, `textureCube`, …) |
| `IMAGE2D_RW(name, fmt, N)` / `imageStore`/`imageLoad` | `[[vk::image_format("fmt")]] RWTexture2D<vec4> name : register(uN);` + `name[coord]` |
| `BUFFER_RW(name, T, N)` / `BUFFER_RO` | `RWStructuredBuffer<T> name : register(uN);` / `StructuredBuffer<T> name : register(tN);` |
| predefined uniforms (`u_modelViewProj`, `u_model`, …) | **do NOT declare — auto-provided.** Use directly. `u_model[0]` → `u_model` (single matrix) |
| `uniform vec4 u_foo;` / `uniform mat4 u_bar;` / `uniform vec4 u_arr[N];` | `float4 u_foo;` / `float4x4 u_bar;` / `float4 u_arr[N];` at file scope (no `uniform` keyword) |
| helper defined inline in the `.sc` body | translate it inline in the `.slang` (it's genuinely local) |

## Modularity — do not inline shared helpers

A helper's home decides how it is ported:

- **Central library** — `src/bgfx_shader.sh`, `examples/common/shaderlib.sh`: `import bgfx_shader;` / `import shaderlib;`.
- **A separate `#include`d `.sh` file** (e.g. `examples/21-deferred/common.sh`, `examples/03-raymarch/iq_sdf.sh`, `examples/41-tess/terrain_common.sh`): port that file **once** to a **co-located `<name>.sh.slang`** in the same `shaders/<example>/` dir (matching the stock filename), each function `public`, and `import <name>;`.
- **Defined inline in the `.sc` body itself**: keep it inline in the `.slang`.

The test: *is it in a separate `#include`d `.sh` file?* → it becomes a library. Never inline
a shared helper file — one bug copied N times is exactly what 1-to-1 porting exists to avoid.

## Library API (import what you use)

- **`bgfx_shader`** — GLSL type aliases `vec2/3/4`, `ivec2/3/4`, `uvec2/3/4`, `mat2`/`mat3`/`mat4`/`mat4x3`; `M_PI`; `rcp`; `vec2/3/4_splat`, `uvec2/3/4_splat`; `mtxFromCols`, `mtxFromRows` (mat2/mat3/mat4/mat4x3), `mtxGetRow`, `mtxGetColumn`, `mtxGetElement` (mat3/mat4x3/mat4); `toGamma`, `toLinear`, `luma`; `texture2D`, `texture2DLod`, `texture2DGrad`, `textureCube`, `textureCubeLod`.
- **`bgfx_shader_glsl_compat`** — the GLSL builtins Slang lacks under its HLSL names: `mix` (incl. the `mix(vec, vec, bvec)` select form), `mod`, `dFdx`, `dFdy`, `lessThan`/`lessThanEqual`/`greaterThan`/`greaterThanEqual`, `floatBitsToUint`/`floatBitsToInt`/`uintBitsToFloat`/`intBitsToFloat`.
- **`shaderlib`** — the full `shaderlib.sh`: `encode/decodeNormalUint`, `encode/decodeNormalOctahedron`, `encode/decodeNormalSphereMap`, `octahedronWrap`, `encodeRE8`/`decodeRE8`, `encodeRGBE8`/`decodeRGBE8`, all `convert*` color-space, `toReinhard`/`toFilmic`/`toAcesFilmic`, `toGammaAccurate`/`toLinearAccurate`, `packFloatToRgba`/`unpackRgbaToFloat`, `packHalfFloat`/`unpackHalfFloat`, `toClipSpaceDepth`, `clipToWorld`, `texture2DBc5`, `random`, `posterize`, `sepia`, `conSatBri`, `adjustHue`, `blendOverlay`, `cofactor`, `fixCubeLookup`.
- **`bgfx_compute`** (compute shaders) — `imageStore`/`imageLoad`/`imageSize` (generic over the texel type: `imageStore`/`imageSize` for `RWTexture2D`/`RWTexture2DArray`/`RWTexture3D`, `imageLoad` also for read-only `Texture2D`/`Texture2DArray`, i.e. `IMAGE2D_RO`); `barrier`, `memoryBarrier`/`memoryBarrierShared`/`memoryBarrierImage`/`memoryBarrierBuffer`; and the indirect writers `dispatchIndirect`, `drawIndirect`, `drawIndexedIndirect`. See the Compute section for the atomics (they are a translation rule, not importable).
- **Native Slang (no import)** — `saturate`, `clamp`, `frac`, `ddx`/`ddy`/`fwidth`, `atan2`, `pow`, `step`, `smoothstep`, `normalize`, `dot`, `cross`, `length`, `reflect`, `refract`, `min`/`max`, `exp`/`log`, `mul(matrix, vector)`, `tex.Sample/.SampleLevel/.Load`. Slang does **not** have GLSL `mix`/`mod`/`lessThanEqual`/`dFdx` — use `bgfx_shader_glsl_compat`.

Libraries are preloaded in dependency order, so a co-located or layered library may freely
`import bgfx_shader;` / `import shaderlib;` — order across `-i` dirs does not matter.

## File naming (matters for the runner)

- Combined `<name>.slang` (both `[shader("vertex")]` and `[shader("fragment")]`) is tested against **both** `vs_<name>.sc` and `fs_<name>.sc` — use only when the VS and FS share the **same** uniform set.
- Per-stage `vs_<name>.slang` / `fs_<name>.slang` / `cs_<name>.slang` (one entry point) is tested against exactly that stock stage. **When the VS and FS declare different uniforms, use per-stage files** — Slang keeps unused UBO members, which would shift offsets in a combined port. When unsure, prefer per-stage.

Match the stock base names (`vs_mesh.sc` → `vs_mesh.slang`).

## Compute shaders

- **Entry:** `[shader("compute")] [numthreads(x,y,z)] void computeMain(uint3 dtid : SV_DispatchThreadID, uint3 ltid : SV_GroupThreadID, uint3 gid : SV_GroupID) {…}`. `NUM_THREADS(x,y,z)` → `[numthreads(x,y,z)]`. `gl_GlobalInvocationID`→`SV_DispatchThreadID`, `gl_LocalInvocationID`→`SV_GroupThreadID`, `gl_WorkGroupID`→`SV_GroupID`, `gl_LocalInvocationIndex`→`SV_GroupIndex`.
- **`import bgfx_compute;`** for `imageStore`/`imageLoad`/`imageSize` and the `barrier`/`memoryBarrier*` family.
- **Buffers:** `BUFFER_RO(name, T, N)` → `StructuredBuffer<T> name : register(tN);`; `BUFFER_RW`/`BUFFER_WR`/`BUFFER_WO(name, T, N)` → `RWStructuredBuffer<T> name : register(uN);`.
- **Images:** `IMAGE2D_RW/WO/WR(name, fmt, N)` → `[[vk::image_format("fmt")]] RWTexture2D<T> name : register(uN);` (read-only → `Texture2D`). Access via `imageLoad(name, uv)` / `imageStore(name, uv, value)` (or native `name[uv]`).
- **Atomics are a translation rule** (they need the memory lvalue, so they can't be importable functions): `atomicAdd(mem, v)` → `InterlockedAdd(mem, v)`; `atomicFetchAndAdd(mem, v, orig)` → `InterlockedAdd(mem, v, orig)`; likewise `And/Or/Xor/Min/Max/Exchange`, and `atomicFetchCompareExchange(mem, cmp, v, orig)` → `InterlockedCompareExchange(mem, cmp, v, orig)`. `mem` must be a `groupshared` variable or an `RWStructuredBuffer`/UAV element.
- **`SHARED`/`shared`** → the `groupshared` keyword (`groupshared T name[...];` at file scope).
- **Indirect** — `import bgfx_compute;` and call `dispatchIndirect(buf, offset, numX, numY, numZ)` / `drawIndirect(...)` / `drawIndexedIndirect(buf, offset, numIndices, numInstances, startIndex, startVertex, startInstance)`, where `buf` is an `RWStructuredBuffer<uvec4>`. (Do not hand-expand the `uvec4` stores — the library provides these now.)

## Gotchas

- **System-value inputs must be struct fields.** Even `SV_VertexID` / `SV_InstanceID` / `SV_DispatchThreadID` etc. that you read go in the input `struct`, not as bare entry-point parameters — vertex-attribute reflection scans struct-typed inputs, so a bare param reflects zero attributes and mismatches the envelope.

- **Array liveness.** glslang reflects an array at its *used* extent but reserves the *declared* size in the `$Globals` layout; Slang reflects the *declared* extent. Declare a custom array at the size the shader actually uses (`u_arr[0]` used → `float4 u_arr[1]`). If a later uniform must keep its byte offset behind a partly-used array, reproduce the reserved tail with an unused padding member (see `09-hdr/fs_hdr_bright`).
- **`mtxFromCols`.** Slang's matrix constructor is row-major (HLSL); `mtxFromCols` transposes to match GLSL's column-setting `mat4(cols)`. Use the library helper — don't hand-roll matrix construction.
- **Loose-uniform offsets are relaxed** by the runner (bgfx binds each by name), but sampler/buffer **bindings** and the **UBO size** are checked — keep `register(tN/sN/uN)` and array sizes exact.
- **Predefined uniforms** are injected by shaderc in `bgfx_shader.sh` order; never declare them, or you shift the offsets.

## Verify

```
python3 tools/shaderc/slang-compliance/run.py --shaderc tools/bin/darwin/shaderc --filter <example>
```
Every case must print `PASS`. A `FAIL` shows a compile error or the envelope diff — iterate
until green. Run without `--filter` for the whole suite.

## Reference ports

- `shaders/06-bump/` — VS tangent space, array uniforms, inline lighting helpers.
- `shaders/03-raymarch/` — inline SDF main + a co-located `iq_sdf.sh.slang`, `SV_Depth` output.
- `shaders/21-deferred/` — MRT, texture arrays, UAV images, normal encode/decode, co-located `common.sh.slang`.
- `shaders/41-tess/terrain_common.sh.slang` — a co-located library declaring `public` samplers/buffers with explicit bindings.
