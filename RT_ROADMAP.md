# bgfx × Ray Tracing — Runtime Roadmap

> Status: **Complete through phase 6 (Metal verified on-device); D3D12/DXR port complete
> (see `RT_WINDOWS_ROADMAP.md`).** The acceleration-structure runtime exists end-to-end:
> public API (`createBlas`/`createTlas`/`setAccelerationStructure`), **Vulkan + Metal + D3D12**
> backends, and the Cornell Box example rendering via hardware ray query with the analytic
> compute fallback kept for hardware without `BGFX_CAPS_RAY_TRACING`. The Metal path is verified
> on-device; the Vulkan path is validated against Mesa's lavapipe (software `VK_KHR_ray_query`)
> and, alongside the D3D12/DXR backend, **on real RT hardware (RTX 4090)** with cross-backend
> image agreement (D3D12 ≡ Vulkan) — see `tools/rt-validation/`. The D3D12/DXR backend (both
> inline ray query and the ray-tracing pipeline) is tracked to completion in
> `RT_WINDOWS_ROADMAP.md`. Written to be idiomatic to bgfx so the work has a realistic chance of
> being **upstreamed** (companion to `SLANG_ROADMAP.md`).

## 1. Goal

Let bgfx users ray trace on the GPU. The first target is **inline ray query** (`RayQuery` /
`OpRayQueryProceedKHR` / Metal `intersection_query`) issued from a **compute shader** —
deliberately *not* the ray-tracing pipeline (raygen/hit/miss + shader binding table).

Why ray-query-first:
- It runs on the **ordinary compute pipeline** — no SBT, no new pipeline object, no new
  shader stages at the runtime. The only genuinely new runtime object is the
  **acceleration structure**.
- It reuses the frozen shader envelope (a ray-query shader is a `CSH`).
- It is the shorter road to a rendered image on **both** Vulkan and Metal, and it is the
  path the [54-cornellbox](examples/54-cornellbox) example's accelerated mode will take,
  with the analytic compute shader as the fallback when `BGFX_CAPS_RAY_TRACING` is absent.

The RT *pipeline* stages already compile in shaderc (see `SLANG_ROADMAP` / the RT-stages
work) but are a later, larger runtime workstream (SBT, pipeline, per-stage dispatch).

## 2. Feasibility — confirmed

- **VK shader:** Slang → SPIR-V emits `OpTypeAccelerationStructureKHR`,
  `OpRayQueryInitializeKHR/ProceedKHR/GetIntersectionTypeKHR` + `SPV_KHR_ray_query`
  (Slang auto-adds the `spvRayQueryKHR` capability).
- **Metal shader:** SPIR-V → SPIRV-Cross emits `#include <metal_raytracing>`,
  `raytracing::acceleration_structure<...>`, `raytracing::intersection_query<...>` —
  **at MSL ≥ 2.4**. The default `-p metal` (low MSL) *silently truncates* the shader; a
  shaderc fix is required (bump the default MSL for ray-query shaders, and error rather than
  emit a truncated envelope).
- **metal-cpp** already exposes the entire AS API (`3rdparty/metal-cpp/metal.hpp`) — no
  header extension needed: `MTL::AccelerationStructure` (`:10503`),
  `PrimitiveAccelerationStructureDescriptor` (`:10066`),
  `Device::accelerationStructureSizes` (`:15472`) / `newAccelerationStructure` (`:15547`),
  `AccelerationStructureCommandEncoder::buildAccelerationStructure` (`:11844`),
  `ComputeCommandEncoder::setAccelerationStructure` (`:13966`) / `useResource` (`:14007`).
- **SPIRV-Cross** already has the ray-query→MSL path (`3rdparty/spirv-cross/spirv_msl.cpp`
  `is_intersection_query`, the `MSL_RAY_QUERY_*` emission).

Net: this is "add a new resource type + build/bind an acceleration structure", **not**
"invent a shader path".

## 3. What this (foundation) branch already provides

Merged from the three prerequisite branches, all verified green together on this tree:
- `BGFX_CAPS_RAY_TRACING` + VK RT extensions/features + Metal `supportsRaytracing` detection
  (`research-rt-feature-config`).
- `DescriptorType::AccelerationStructure` (`src/shader.h`) + the Slang front-end reflecting
  `RaytracingAccelerationStructure` as a bound uniform instead of dropping it, plus the RT
  shader-stage magics (`shaderc-slang-rt-stages`).
- Slang → Metal (MSL) codegen + the std140 uniform-array reflection fix
  (`slang-spirv-x-metal`, `slang-metal-uniform-arrays`).

## 4. Public API (idiomatic bgfx)

A new resource type `AccelerationStructureHandle`, mirroring the `VertexBuffer` end-to-end
pattern. Sketch:
```cpp
AccelerationStructureHandle createBlas(VertexBufferHandle, IndexBufferHandle, /* geometry */ ...);
AccelerationStructureHandle createTlas(const AsInstance* instances, uint32_t num);
void destroy(AccelerationStructureHandle);
// bind to a (compute) shader, like setBuffer:
void setAccelerationStructure(uint8_t stage, AccelerationStructureHandle);
```

### Resource-add touch points (worked from `VertexBuffer`)
| File | Change |
|------|--------|
| `include/bgfx/bgfx.h` | `BGFX_HANDLE(AccelerationStructureHandle)` (~:517 block) |
| `scripts/bgfx.idl` | handle decl (~:1173) + `func.createBlas/createTlas` + `func.destroy` overload; regen bindings |
| `src/config.h` | `BGFX_CONFIG_MAX_ACCELERATION_STRUCTURES` (~:342 pattern) |
| `src/bgfx_p.h` | `CommandBuffer::Enum` create/destroy; `RendererContextI` virtuals (~:4148); `Context` handle allocator + records + create/destroy/internal (~:4533); `Binding::Enum::AccelerationStructure` + setter (keep `sizeof(Binding)==16`, ~:1913) |
| `src/bgfx.cpp` | public wrappers (~:4766); `rendererExecCommands` cases (~:3451, write/read order must match); deferred-free (~:2660); encoder `setAccelerationStructure` + free-fn forwarder (~:4483) |
| all 8 `renderer_*.cpp` | implement the two new pure virtuals (noop stub minimum) |

## 5. Vulkan backend (`src/renderer_vk.cpp`)

- **Import PFNs** into `VK_IMPORT_DEVICE` (`renderer_vk.h:127`, optional): `vkCreate/Destroy/
  CmdBuildAccelerationStructuresKHR`, `vkGetAccelerationStructureBuildSizesKHR`,
  `vkGetAccelerationStructureDeviceAddressKHR`, `vkGetBufferDeviceAddressKHR` — auto-resolve
  at `:2180`. (The feature-config work enabled the extensions/features but did **not** import
  these entry points.)
- **Device-address buffers:** add a `createDeviceLocalBuffer(size, usage, deviceAddress)`
  helper beside `createHostBuffer` (`:4840`) — AS-storage / scratch / build-input usage bits
  + `VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT`, and chain
  `VkMemoryAllocateFlagsInfo{DEVICE_ADDRESS}` into `allocateMemory`'s `ma.pNext` (`:4813`).
  bgfx uses manual `VkDeviceMemory` (not VMA).
- **`AccelerationStructureVK`** mirrors `BufferVK::create` (`:5498`): sizes from
  `vkGetAccelerationStructureBuildSizesKHR`; `vkCmdBuildAccelerationStructuresKHR` on
  `m_commandBuffer` + an AS-build→compute `setMemoryBarrier`. Scratch alignment from
  `VkPhysicalDeviceAccelerationStructurePropertiesKHR.minAccelerationStructureScratchOffsetAlignment`.
- **Descriptor:** `DescriptorType::AccelerationStructure` → `BindType::AccelerationStructure`
  (`renderer_vk.h:514`); layout switch (`:5892`) emits
  `VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR`; write loop (`getDescriptorSet`, ~:4362)
  chains `VkWriteDescriptorSetAccelerationStructureKHR` via `pNext`; add to the pool table
  (`:4232`).

## 6. Metal backend (`src/renderer_mtl.cpp` / `.h`)

- **`AccelerationStructureMtl`** mirrors `BufferMtl` (`renderer_mtl.h:250`):
  `Device::accelerationStructureSizes` + `newAccelerationStructure` + a scratch `MTL::Buffer`.
- **Build encoder:** add `m_accelerationStructureCommandEncoder`, mirror the
  `getBlitCommandEncoder`/`endEncoding` lifecycle (`:3047`/`:3134`); `buildAccelerationStructure`
  at create/update time (only one encoder live per command buffer).
- **Bind:** in the compute bind loop (`:5406`), a new `Binding::AccelerationStructure` case
  calls `setAccelerationStructure(as, index)` **and** `useResource(as, Read)` (plus
  `useResource` for each BLAS an instance-AS references) before the dispatch (`:5477`). The
  residency call has no analog in the current bind path — easy to miss → GPU fault.

## 7. shaderc

- Land the accel-structure reflection (done on this tree).
- **Bump the default Metal MSL version to ≥ 2.4 for ray-query shaders** (or globally for RT),
  and make shaderc *error* on version-too-low rather than emit a truncated envelope.

## 8. Cornell Box payoff

Add a ray-query variant of `examples/54-cornellbox/cs_cornellbox.slang` (trace `scene` via
`RayQuery` instead of the analytic intersector); the app builds a BLAS+TLAS for the box
geometry and selects the path on `getCaps()->supported & BGFX_CAPS_RAY_TRACING`, falling
back to the analytic compute shader otherwise.

## 9. Phasing

1. ✅ integrate the three prerequisites (`experimental/research-rt-runtime`) — green.
2. ✅ shaderc MSL-version fix (`experimental/rt-runtime-msl-fix`) — ray-query shaders
   auto-bump to MSL 2.4 instead of aborting SPIRV-Cross.
3. ✅ Public API + backend stubs (`experimental/rt-runtime-api`) — `AccelerationStructureHandle`
   end-to-end through the IDL/codegen, all 8 backends stubbed.
4. ✅ **Vulkan** BLAS/TLAS + descriptor bind (`experimental/rt-runtime-vk`) — compiles clean;
   runtime validation awaits an RT-capable Vulkan host (see Risks).
5. ✅ **Metal** AS + bind (`experimental/rt-runtime-mtl`) — **verified on-device**: triangle
   BLAS/TLAS + ray-query dispatch reads back 4096/4096 hits.
6. ✅ Cornell Box ray-query variant + caps-gated selection
   (`experimental/rt-runtime-cornellbox`) — the RT path and the analytic compute fallback
   (kept, selected when the cap is absent) render the same image, verified on Metal.

### Follow-ups

- Vulkan path validated via lavapipe (`tools/rt-validation/`, cross-backend image
  agreement with Metal at mean |delta| 0.12/255); a run on real `VK_KHR_ray_query`
  hardware remains a nice-to-have for performance and driver-diversity coverage.
- Path-traced global illumination in the example (colour bleeding) -- done, along with
  SVGF denoising and ReSTIR DI (see `examples/54-cornellbox`).
- Generalized API -- done: `createTlas` takes multiple BLAS instances with per-instance
  transforms (`updateTlas`); `createBlas` takes multiple geometries and supports in-place
  refit (`updateBlas`) after e.g. compute-shader deformation of the source vertex buffers.
  All validated on Metal (on-device) and Vulkan (lavapipe), `tools/rt-validation/`.
- The RT *pipeline* v1 is DONE (Vulkan-only, lavapipe-verified): `createRtProgram(raygen,
  miss, closestHit)` + `bgfx::dispatch` (ray-grid in rays) with the SBT built at pipeline
  creation; new `BGFX_CAPS_RAY_TRACING_PIPELINE` cap. v2 (also lavapipe-verified): resources may be
  declared in ANY stage (the descriptor-set layout is the dedup-by-binding union with
  stage flags OR-ed), multiple miss shaders and triangle hit groups, recursion depth 2
  (a shadow/secondary ray from a hit shader). Uniforms still come from the raygen stage.
  Callables and any-hit stages are in (optional per-hit-group any-hit, callables as the
  fourth SBT region; note any-hit requires non-opaque traversal, e.g.
  `RAY_FLAG_FORCE_NON_OPAQUE`, since bgfx BLAS geometry is built opaque). Procedural
  intersection completes the stage set: `createBlasAabbs` builds a BLAS from packed AABB
  buffers (both backends) and a valid entry in `createRtProgram`'s intersection array
  makes that hit group procedural (Vulkan pipeline; Metal ray query would need
  bounding-box candidate handling in the shader). Remaining: deeper recursion. The
  Metal RT-pipeline path is SPIKED — runtime model proven on-device via function tables
  (see `METAL_RT_PIPELINE.md`); blocked on Slang Metal-target RT-stage codegen, not on
  which cannot come from SPIRV-Cross (no MSL for RT pipeline stages) and would instead
  map onto Metal intersection function tables, likely via Slang's native MSL backend.

## 10. Risks

- ~~KosmicKrisp (macOS Vulkan) does not expose the RT extensions → the Vulkan RT path
  cannot be validated on this Mac.~~ Resolved: lavapipe (Mesa software Vulkan, arm64
  Linux container) implements the full RT extension stack on the CPU and validates the
  Vulkan backend on this machine — including as a CI-able regression rig
  (`tools/rt-validation/`).
- TLAS instance/transform + geometry device-address plumbing is the fiddliest VK part.
- `Binding` is a fixed 16-byte hashed struct — the new bind type must fit.
- Metal AS residency (`useResource`) is mandatory and unlike anything in the current bind path.
