# 52-cornellbox

The classic **Cornell Box**, ray traced in a **Slang** shader.

![screenshot](screenshot.png)

Two rendering paths share one scene, selected at runtime:

- **RT accelerated** (`cs_cornellbox_rq.slang`) — the scene as a real triangle mesh traced
  with a hardware **ray query** against a BLAS/TLAS built through the bgfx
  acceleration-structure API (`createBlas` / `createTlas` / `setAccelerationStructure`).
  Selected when `BGFX_CAPS_RAY_TRACING` is present. Per-triangle materials
  (albedo / emission / normal) live in a buffer indexed by the committed primitive index.
- **Compute fallback** (`cs_cornellbox.slang`) — a self-contained analytic ray tracer in a
  compute shader. Runs anywhere `BGFX_CAPS_COMPUTE` is available, with no hardware ray
  tracing; this is what the example drops to when the RT cap is absent.

Both paths implement the same shading (direct lighting from the ceiling area light + hard
shadows + a small ambient term) and produce the same image; the characteristic colour
bleeding is the natural path-traced next step.

## Why Slang

The shaders are authored once in Slang and compiled through bgfx's Slang front-end to every
backend: SPIR-V for Vulkan and, via SPIRV-Cross, MSL for Metal — including the ray-query
path (`RayQuery` / `metal::raytracing::intersection_query`). This example is the first
end-to-end render driven by that path, and the ray-query variant is the first hardware ray
trace through the bgfx acceleration-structure runtime.

## Files

- `cs_cornellbox_rq.slang` — the hardware ray-query tracer (BLAS/TLAS + material buffer).
- `cs_cornellbox.slang` — the analytic compute fallback (writes to an output image).
- `vs_cornellbox.slang` / `fs_cornellbox.slang` — a fullscreen quad that blits the image.
- `cornellbox.cpp` — the app: builds the triangle mesh + BLAS/TLAS when
  `BGFX_CAPS_RAY_TRACING` is present, dispatches whichever tracer applies, then displays.
- `makefile` — builds the Slang shaders for Metal + SPIR-V (`SHADER_TARGETS := 5 7`).

Build wiring: `scripts/shader.mk` gained `*.slang` rules and a `SHADER_TARGETS` override;
the example is registered in `scripts/genie.lua`.

## Status

- Both paths verified on Metal (Apple GPU): the ray-query render and the analytic fallback
  produce the same image (see the screenshot).
- Vulkan compiles end-to-end (SPIR-V ray query + the VK acceleration-structure backend) but
  awaits validation on a Vulkan host with `VK_KHR_ray_query` hardware.

## Notes / lessons learned here

- bgfx flattens the `t`/`u` register spaces into one bind namespace — resources need
  globally unique register numbers or they collapse onto the same bind stage
  (`scene : t0`, `s_target : u1`, `materials : u2`).
- Inline ray query only auto-commits **opaque** geometry; the runtime marks BLAS geometry
  opaque on both backends.
- Don't name a ray-query local `ray` — it collides with MSL's `metal::raytracing::ray`
  type in SPIRV-Cross output.
- The resolution is read from the output image via `imageSize(s_target)` rather than a
  uniform. A Slang-generated MSL wraps a `uniform vec4 u_params[N]` **array** in a std140
  helper struct that bgfx's Metal runtime uniform reflection could not map
  (`MTLDataType::Struct`); that is fixed on the `experimental/slang-metal-uniform-arrays`
  branch (merged into this stack), after which uniforms can replace the `imageSize()`
  approach.
