# 52-cornellbox

The classic **Cornell Box**, ray traced in a **Slang** shader.

![screenshot](screenshot.png)

Two rendering paths share one scene:

- **Compute fallback** (`cs_cornellbox.slang`, implemented) — a self-contained analytic
  ray tracer in a compute shader. Runs anywhere `BGFX_CAPS_COMPUTE` is available, with no
  hardware ray tracing. Direct lighting from the ceiling area light + hard shadows; the
  characteristic colour bleeding is added by the path-traced/accelerated path.
- **RT accelerated** (planned) — the same scene traced with a hardware **ray query**
  against a BVH, selected at runtime when `BGFX_CAPS_RAY_TRACING` is present. Needs the
  bgfx acceleration-structure runtime (not yet implemented); the compute path above is the
  fallback that the example drops to otherwise.

## Why Slang

The shader is authored once in Slang and compiled through bgfx's Slang front-end to every
backend: SPIR-V for Vulkan and, via SPIRV-Cross, MSL for Metal. This example is the first
end-to-end render driven by that path.

## Files

- `cs_cornellbox.slang` — the compute ray tracer (writes to an output image).
- `vs_cornellbox.slang` / `fs_cornellbox.slang` — a fullscreen quad that blits the image.
- `cornellbox.cpp` — the app (dispatch compute → display), an `entry::AppI` example.
- `makefile` — builds the Slang shaders for Metal + SPIR-V (`SHADER_TARGETS := 5 7`).

Build wiring: `scripts/shader.mk` gained `*.slang` rules and a `SHADER_TARGETS` override;
the example is registered in `scripts/genie.lua`.

## Status

- Shaders compile to SPIR-V and Metal through the standard example build; `cornellbox.cpp`
  builds; the compute ray tracer renders correctly (verified on Metal — see the screenshot).
- The **RT-accelerated** ray-query path (gated on `BGFX_CAPS_RAY_TRACING`) is the remaining
  work — it needs the bgfx acceleration-structure runtime, plus integrating the sibling
  caps / RT-stages branches.

## Notes / known limitations discovered here

- The resolution is read from the output image via `imageSize(s_target)` rather than a
  uniform. A Slang-generated MSL wraps a `uniform vec4 u_params[N]` **array** in a std140
  helper struct that bgfx's Metal runtime uniform reflection could not map
  (`MTLDataType::Struct`); that is fixed on the `experimental/slang-metal-uniform-arrays`
  branch, after which uniforms can replace the `imageSize()` approach.
