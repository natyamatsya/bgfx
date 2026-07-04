# 2. Slang shader library composition: uniforms per-shader, library provides samplers + helpers

- **Status:** Accepted
- **Date:** 2026-07-04
- **Context branch:** `experimental/research-slang-support`
- **Related:** [ADR 0001](0001-slang-reflection-source.md), [`SLANG_ROADMAP.md`](../../SLANG_ROADMAP.md), [compliance suite](../../tools/shaderc/slang-compliance/README.md)

## Context

bgfx ships shared shader libraries — `src/bgfx_shader.sh`, `examples/common/shaderlib.sh`,
`src/bgfx_compute.sh` — that (a) declare **all** predefined uniforms (`u_view`, `u_proj`,
`u_modelViewProj`, …), (b) provide the sampler abstraction (`SAMPLER2D` + `bgfxTexture2D` wrappers),
and (c) provide helper functions (color-space, normal encode/decode, etc.). Nearly every example
`#include`s them (via `common.sh`).

Crucially, bgfx relies on **glslang's live-uniform reflection**: even though a shader includes a header
declaring all predefined uniforms, the compiled envelope contains only the uniforms the shader actually
**uses** (the stock `01-cubes` envelope has just `u_modelViewProj`). Porting the libraries to Slang and
having each `.slang` shader `import` them must reproduce that same only-used-uniforms envelope to
byte-match the stock compiler (the compliance criterion).

Empirical findings while designing the Slang shared library (tested against `libslang`):

1. **`.sh.slang` files are importable.** `import bgfx_shader;` resolves to a `bgfx_shader.sh.slang`
   file when the file's content is preloaded as a module named `bgfx_shader` via
   `ISession::loadModuleFromSourceString(name, path, source)` — the module name is decoupled from the
   filename. (Filesystem-search `import` alone looks for `bgfx_shader.slang` and does not find the
   double extension.) Library symbols must be `public`; uniforms want the `uniform` modifier.
2. **Slang does not strip unused module uniforms.** A shader that imports the library and uses only
   `u_modelViewProj` still carries `u_view`/`u_proj` in its SPIR-V UBO and reflection.
3. **`IMetadata::isParameterLocationUsed` cannot strip individual cbuffer members** — it returns
   `used = false` for every uniform member (a byte offset is not a valid "location" for the uniform
   category), including the member that *is* used.

Finding 2 is **intended Slang behavior, not an oversight**: Slang assigns parameter/resource bindings
**before** dead-code elimination so that a parameter's binding is stable regardless of which entry point
or specialization uses it (essential for Slang's separate-compilation / link-time-specialization model).
It is documented as a deliberate difference from DXC/glslang.

## Decision

Split the bgfx shader library along the grain of what Slang *does* dead-strip:

- **The shared Slang libraries (`bgfx_shader.sh.slang`, `shaderlib.sh.slang`, `bgfx_compute.sh.slang`)
  contain only the sampler abstraction, types, and helper *functions*.** Slang dead-strips unused
  functions/types correctly (they are only pulled in when called), so importing a library does not bloat
  a shader's envelope.
- **Predefined uniforms are declared per-shader** in each `.slang` port — only the ones that shader uses.
  This matches bgfx's actual per-shader uniform usage and byte-matches the stock (glslang-stripped)
  envelope. Which uniforms to declare is read mechanically off the source `.sc`.
- **Libraries are consumed via `import`**, preloaded by `shaderc_slang.cpp`: each `*.sh.slang` in the
  include dirs is registered as a module named after the file (minus `.sh.slang`), so shaders write
  `import bgfx_shader;`.

## Consequences

### Positive
- **Byte-matches the stock envelope** — the compliance suite stays green because Slang emits the same
  only-used uniform set as glslang.
- **Slang-idiomatic** — an explicit per-shader parameter interface is how Slang is designed to be used;
  we work with the layout-stability model instead of against it.
- **Library still delivers the high-value shared code** — the sampler abstraction (the 106 textured
  examples) and `shaderlib` helpers, none of which bloat envelopes.
- **No fragile SPIR-V surgery** — we do not have to post-process the SPIR-V to remove UBO members.

### Negative / costs
- Predefined-uniform declarations are duplicated across shaders (one line each). A small, mechanical cost.
- Porting must identify the used uniforms per shader (trivially derived from the `.sc`).

## Alternatives considered

### A. Library declares all predefined uniforms (rejected)
The natural GLSL-idiom port. Rejected: because Slang binds before DCE (finding 2), every shader that
imports the library would carry *all* predefined uniforms plus an oversized UBO, a hard byte-mismatch
with the stock envelope, and there is no supported per-member strip (finding 3).

### B. SPIR-V-level unused-uniform stripping in `shaderc_slang.cpp` (rejected)
Keep uniforms in the library and post-process the emitted SPIR-V to remove unaccessed UBO members and
recompute offsets/size. Rejected: heavy, fragile SPIR-V surgery and an ongoing maintenance burden, taken
on purely to fight Slang's intended parameter model.

## Notes

Reflection is still taken from Slang's API per ADR 0001; this ADR only governs how the shared shader
library is factored and consumed. If a future need arises to share uniforms (e.g. large uniform blocks),
revisit via a `ParameterBlock`-based design rather than loose globals.
