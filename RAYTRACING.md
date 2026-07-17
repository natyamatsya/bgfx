# Ray tracing with bgfx + Slang

A practical guide to authoring ray-traced content for bgfx with [Slang](https://github.com/shader-slang/slang)
shaders. It covers the acceleration-structure API, the two tracing paths, and the shader idioms for each.

For the design background see [`RT_ROADMAP.md`](RT_ROADMAP.md) and [`SLANG_ROADMAP.md`](SLANG_ROADMAP.md);
for a complete, runnable program see [`examples/52-cornellbox`](examples/52-cornellbox).

## The two paths

bgfx exposes ray tracing as **acceleration structures** (BLAS/TLAS) plus one of two ways to trace them:

| | **Inline ray query** | **Ray-tracing pipeline** |
|---|---|---|
| Where rays are traced | inside a **compute** shader | dedicated **ray-gen / hit / miss** stages |
| Slang stage(s) | `[shader("compute")]` + `RayQuery` | `raygeneration`, `closesthit`, `miss`, (opt.) `anyhit`, `intersection`, `callable` |
| Bind AS with | `bgfx::setAccelerationStructure` | referenced by the shaders (`register(t0)`) |
| Build program with | `bgfx::createProgram` | `bgfx::createRtProgram` |
| Cap required | `BGFX_CAPS_RAY_TRACING` | `BGFX_CAPS_RAY_TRACING_PIPELINE` |
| Good for | GI, path tracing, effects that stay in compute | procedural geometry, hardware hit-shader dispatch, callables |

Ray query is the broadly-available path; the pipeline path adds hardware-scheduled hit shaders. Both consume
the same acceleration structures, so you can build the scene once and drive it either way.

## Check the capabilities

Everything below is gated by run-time caps — always query them and keep a non-RT fallback (the Cornell Box
example drops to a pure-compute analytic tracer when `BGFX_CAPS_RAY_TRACING` is absent):

```cpp
const uint64_t caps = bgfx::getCaps()->supported;
const bool rayQuery = 0 != (caps & BGFX_CAPS_RAY_TRACING);          // AS build + inline ray query
const bool rtPipe   = 0 != (caps & BGFX_CAPS_RAY_TRACING_PIPELINE); // createRtProgram
```

> **macOS note:** Metal provides `BGFX_CAPS_RAY_TRACING`. MoltenVK (Vulkan on macOS) implements **no** ray-tracing
> extensions, so under it both caps are absent — use the Metal backend, or the compute fallback.

## Build the acceleration structures

A **BLAS** holds geometry; a **TLAS** instances one or more BLASes with per-instance transforms.

```cpp
// One BLAS per mesh, from triangle geometry (vertex + index buffers).
bgfx::AccelerationStructureHandle blas = bgfx::createBlas(&vbh, &ibh, 1 /*numGeometries*/);

// A TLAS instancing the BLASes. Instances start at identity; set transforms with updateTlas.
bgfx::AccelerationStructureHandle blases[] = { blas0, blas1, blas2 };
bgfx::AccelerationStructureHandle tlas = bgfx::createTlas(blases, BX_COUNTOF(blases) );

// Per-instance transforms: one 4x4 matrix per instance, in createTlas order.
float mtx[3][16];
bx::mtxSRT(mtx[0], /*...*/);
// ...fill mtx[1], mtx[2]...
bgfx::updateTlas(tlas, bgfx::copy(mtx, sizeof(mtx) ) );
```

Other builders and updates:

- **Procedural geometry** — `bgfx::createBlasAabbs(aabbBuffers, num)` builds a BLAS from packed AABBs
  (6 floats each: min xyz, max xyz). Hits inside the boxes are reported by an **intersection** shader
  (pipeline path only).
- **Refit** — after deforming a BLAS's vertex buffers (e.g. skinned by a compute shader writing a
  `BGFX_BUFFER_COMPUTE_WRITE` buffer) call `bgfx::updateBlas(blas)` — cheaper than a rebuild, but the topology
  (index buffers, counts) must be unchanged — then `bgfx::updateTlas` any TLAS that references it.
- **Animate** — call `bgfx::updateTlas` each frame with fresh transforms to move/rotate instances.
- **Destroy** — `bgfx::destroy(handle)` for both BLAS and TLAS.

## Path A — inline ray query (compute)

Bind the TLAS to a compute stage, then trace it inline from a Slang compute shader.

```cpp
bgfx::setAccelerationStructure(0, tlas);           // stage 0 -> register(t0)
bgfx::setImage(1, outputTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
bgfx::dispatch(viewId, rayQueryProgram, (w+7)/8, (h+7)/8, 1); // dims are WORKGROUPS
```

The Slang shader binds the AS as a `RaytracingAccelerationStructure` and traces with `RayQuery`:

```slang
uniform RaytracingAccelerationStructure scene : register(t0);
RWTexture2D<float4> s_target : register(u1);

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
	RayDesc ray;
	ray.Origin    = /* camera / surface point */;
	ray.Direction = /* normalize(...) */;
	ray.TMin      = 1e-3;
	ray.TMax      = 1e30;

	RayQuery<RAY_FLAG_NONE> rq;
	rq.TraceRayInline(scene, RAY_FLAG_NONE, 0xff /*instance mask*/, ray);
	rq.Proceed(); // opaque triangle hits auto-commit; loop + rq.CommitNonOpaque* for non-opaque

	if (rq.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
	{
		uint  inst = rq.CommittedInstanceIndex();
		uint  prim = rq.CommittedPrimitiveIndex();
		float2 bary = rq.CommittedTriangleBarycentrics();
		float t     = rq.CommittedRayT();
		// ...shade...
	}
}
```

Compile it like any other Slang compute shader (see [Compiling](#compiling-slang-rt-shaders)):

```sh
shaderc --lang slang -f cs_trace.slang -o cs_trace.bin --type compute --profile spirv -i src
```

## Path B — the ray-tracing pipeline

Author the stages as separate Slang shaders sharing a **ray payload** struct, link them into a program with
`createRtProgram`, and dispatch it. The AS is referenced directly by the shaders.

**Ray generation** — one invocation per pixel; casts the primary ray:

```slang
uniform RaytracingAccelerationStructure scene : register(t0);
RWTexture2D<float4> s_target : register(u1);

struct Payload { float3 color; };

[shader("raygeneration")]
void rayGenMain()
{
	uint2 px = DispatchRaysIndex().xy;

	RayDesc rd;
	rd.Origin = /*...*/; rd.Direction = /*...*/; rd.TMin = 1e-3; rd.TMax = 1e30;

	Payload p = { float3(0, 0, 0) };
	// TraceRay(scene, flags, mask, hitGroupOffset, hitGroupStride, missIndex, ray, payload)
	TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 0, 0, rd, p);

	s_target[px] = float4(p.color, 1.0);
}
```

**Closest hit** — runs for the nearest triangle in the hit group:

```slang
[shader("closesthit")]
void closestHitMain(inout Payload p, in BuiltInTriangleIntersectionAttributes attribs)
{
	float2 bary = attribs.barycentrics;
	uint   inst = InstanceIndex();
	uint   prim = PrimitiveIndex();     // e.g. materials[inst*trisPerInstance + prim]
	p.color = /*...shade...*/;
}
```

**Miss** — runs when a ray hits nothing:

```slang
[shader("miss")]
void missMain(inout Payload p) { p.color = /* sky / background */; }
```

Optional stages: **`anyhit`** (called for non-opaque hits along the ray, e.g. alpha test), **`intersection`**
(custom hit for procedural `createBlasAabbs` geometry — call `ReportHit`), and **`callable`** (invoked with
`CallShader`). Compile each with its matching `--type`, then link:

```cpp
bgfx::ShaderHandle miss[] = { loadShader("rt_miss") };
bgfx::ShaderHandle chit[] = { loadShader("rt_chit") };            // one per hit group
bgfx::ProgramHandle rt = bgfx::createRtProgram(
	  loadShader("rt_raygen")
	, miss, BX_COUNTOF(miss)
	, chit                       // closest-hit shaders
	, NULL                       // any-hit    (parallel to chit; NULL = none)
	, NULL                       // intersection (parallel to chit; a valid entry = procedural group)
	, BX_COUNTOF(chit)           // number of hit groups
	, NULL, 0                    // callables
	, true                       // destroy shaders with the program
	);

// Dispatch: for an RT program the dimensions are the ray grid in RAYS (not workgroups).
bgfx::setImage(1, outputTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
bgfx::dispatch(viewId, rt, width, height, 1);
```

### Hit groups and instancing

A **hit group** is a closest-hit shader plus its optional any-hit / intersection partners, supplied in parallel
arrays to `createRtProgram`. Which group a ray runs is derived from the geometry it hits and `TraceRay`'s
`hitGroupOffset`. Inside a hit shader, `InstanceIndex()` and `PrimitiveIndex()` identify what was hit — the
example convention indexes a shared material buffer as `InstanceIndex() * trianglesPerInstance + PrimitiveIndex()`.

## Compiling Slang RT shaders

The Slang front-end (`--lang slang`, or inferred from a `.slang` extension) accepts the ray-tracing stages via
`--type`:

```
raygeneration  intersection  anyhit  closesthit  miss  callable
```

Ray-query shaders are ordinary compute shaders — use `--type compute`. Targets follow the usual `--profile`
(`spirv` for Vulkan, the Metal profile for Metal). The predefined bgfx uniforms are auto-provided, and the shared
Slang libraries (`bgfx_shader`, `bgfx_compute`) are on the include path via `-i src` — see
[`tools/shaderc/slang-compliance/SLANG_PORTING.md`](tools/shaderc/slang-compliance/SLANG_PORTING.md) for the
general `.sc` → Slang porting patterns.

## Worked example

[`examples/52-cornellbox`](examples/52-cornellbox) is the reference: a Cornell Box that builds three BLASes and a
rotating TLAS, and renders it three ways from one scene —

- **ray query** (`cs_cornellbox_rq.slang`) — inline `RayQuery` in compute, the default when
  `BGFX_CAPS_RAY_TRACING` is present;
- **RT pipeline** (`rt_cornellbox_rg` / `_chit` / `_miss` / `_shadow`) — the `createRtProgram` path, gated on
  `BGFX_CAPS_RAY_TRACING_PIPELINE`;
- **compute fallback** (`cs_cornellbox.slang`) — a self-contained analytic tracer for compute-only devices.

Its `Diagnostics` panel shows the active renderer, the RT/compute caps, and which path is live.

## See also

- [`RT_ROADMAP.md`](RT_ROADMAP.md) — the ray-tracing runtime design and milestones.
- [`SLANG_ROADMAP.md`](SLANG_ROADMAP.md) — the Slang shader front-end.
- [`docs/adr/`](docs/adr) — decisions behind the Slang integration (reflection source, library composition,
  predefined uniforms).
- [`METAL_RT_PIPELINE.md`](METAL_RT_PIPELINE.md) — how the pipeline path maps onto Metal.
