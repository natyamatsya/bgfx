# bgfx × Metal — Ray-Tracing Pipeline Feasibility (spike)

> Status: **runtime model PROVEN on-device** (Apple M2 Max, 2026-07);
> **blocked on codegen** (Slang's Metal target does not yet lower ray-tracing stages).
> Companion to `RT_ROADMAP.md`. Prototype: `tools/rt-validation/metal_rt_pipeline_spike.cpp`.

## 1. Question

bgfx's ray-tracing pipeline (`createRtProgram`: raygen / miss / closest-hit / any-hit /
intersection / callable + a shader binding table, dispatched with `bgfx::dispatch` where
the dimensions are rays) runs on Vulkan today. Metal has **no** equivalent pipeline
object — no SBT, no driver-side shader dispatch. Can the same public API be implemented
on Metal idiomatically enough to be upstreamable?

## 2. Answer

**Yes — the runtime maps cleanly onto Metal's canonical model** (a compute kernel driving
`metal::raytracing::intersector` plus *function tables*), and the spike proves every
runtime ingredient on-device. **The missing piece is compiler support**, and the
idiomatic path is to get it from Slang's Metal backend rather than building a bespoke
MSL emitter inside shaderc.

### The mapping

| bgfx / Vulkan concept | Metal implementation |
|---|---|
| raygen shader | **the compute kernel** (`bgfx::dispatch` dims are rays — identical semantics, since Metal RT is compute-driven anyway) |
| `TraceRay()` | `intersector<...>::intersect()` + a switch that calls the hit/miss entry through the function table |
| miss / closest-hit / callable shaders | `[[visible]]` functions in a **`MTLVisibleFunctionTable`** (function-pointer dispatch, Apple6+/`supportsFunctionPointers`) |
| intersection / any-hit shaders | `[[intersection(...)]]` functions in a **`MTLIntersectionFunctionTable`**, consumed *natively* by the intersector (per-geometry `intersectionFunctionTableOffset` carries DXR's hit-group-index semantics) |
| shader binding table | a small **"software SBT"** buffer of table indices per group kind — same regions as the Vulkan SBT, holding indices instead of GPU handles |
| `vkCmdTraceRaysKHR` | `dispatchThreads(w, h, 1)` on the linked compute pipeline |
| pipeline creation | `MTLComputePipelineDescriptor` + `MTLLinkedFunctions` (all stage functions linked into the raygen kernel's pipeline); tables built once per program — exactly where the Vulkan backend builds its SBT |
| AS residency | `useResource` for TLAS + BLASes (already implemented in the bgfx Metal backend); tables bound via `setVisibleFunctionTable` / `setIntersectionFunctionTable` |

**No public bgfx API change is needed.** `createRtProgram` + `dispatch` already abstract
both models; the Metal backend's `createRtProgram` would link the stage functions and
build the tables, and the caps bit (`BGFX_CAPS_RAY_TRACING_PIPELINE`) gates on
`supportsRaytracing() && supportsFunctionPointers()`.

## 3. What the spike proves (on-device, first try)

`tools/rt-validation/metal_rt_pipeline_spike.cpp` — standalone metal-cpp, hand-written
MSL standing in for future compiler output, additive-value validation as in
`rt_pipeline_smoke` (0.75 = hit routed through the table **and** analytic distance
correct; 0.25 / 0.5 = distinguishable failures):

- **Phase A — visible-function SBT:** triangle TLAS; the kernel routes
  hit→`chitFn`/miss→`missFn` through a `visible_function_table` indexed by an SBT
  buffer; `chitFn` validates `hit.distance` = 4.2. → 4096/4096.
- **Phase B — intersection function table:** procedural sphere in an AABB BLAS; an
  `[[intersection(bounding_box, instancing)]]` function reports the analytic entry;
  same visible-function routing on top. → 4096/4096.

Also confirmed: the vendored metal-cpp already exposes the entire API surface
(`LinkedFunctions`, `VisibleFunctionTable(+Descriptor)`,
`IntersectionFunctionTable(+Descriptor)`, `functionHandle`, `setVisibleFunctionTable`,
`supportsFunctionPointers`) — no header work needed.

## 4. The codegen gap (the actual blocker)

Neither of shaderc's two Metal routes can compile RT stages today:

- **SPIRV-Cross** (our current Slang→SPIR-V→MSL route) has no MSL backend for
  raygen/miss/hit/intersection/callable SPIR-V execution models.
- **Slang's native Metal target** rejects them outright (Slang 2025.23):
  `error 36107: entrypoint 'rayGenMain' uses features that are not available in 'raygen'
  stage for 'metal' compilation target` — a capability gate on `DispatchRaysIndex`,
  `TraceRay`, etc.

What a compiler must emit is exactly what the spike hand-writes: raygen as a kernel with
`TraceRay` lowered to intersector + table dispatch, miss/chit/callable as `[[visible]]`
functions with the payload passed through the function signature, intersection/any-hit
as `[[intersection(...)]]` functions. That lowering belongs in **Slang** (it owns the
stage semantics, the payload ABI, and already has a Metal backend); a from-scratch
DXR-to-MSL transpiler inside shaderc would be a maintenance liability no upstream wants.

**Open lowering question to validate when codegen lands:** `TraceRay` *from a
closest-hit shader* (recursion depth 2, the shadow-ray pattern). Visible functions can
plausibly run their own intersector; if not, the standard fallback is the megakernel
iteration (the hit function returns a continuation request the kernel loop executes).
Either is expressible without touching the bgfx API.

## 5. Recommended plan (in upstreamable increments)

1. **Now** (this spike): the design + on-device proof + this document. Zero runtime risk
   taken; zero API invented.
2. **Watch/contribute upstream Slang**: Metal RT-stage lowering (the capability gate
   above is where it would land). The bgfx side needs nothing speculative in the
   meantime — the envelope format already carries MSL text for Metal shaders, and the
   RT stage magics (`RSH`/`MSH`/…) are target-agnostic.
3. **When codegen exists**: implement `createRtProgram` in the Metal backend per the
   mapping table (§2) — function creation from the per-stage envelopes, one linked
   compute pipeline per program, tables as the SBT. Enable
   `BGFX_CAPS_RAY_TRACING_PIPELINE` on Metal; `rt_pipeline_smoke` and the Cornell Box
   stage-5 cross-check then validate Metal against lavapipe with zero new test code.
