# 3. Slang: auto-provide bgfx predefined uniforms

- **Status:** Accepted
- **Date:** 2026-07-04
- **Context branch:** `experimental/research-slang-support`
- **Related:** [ADR 0002](0002-slang-shader-library-composition.md) (supersedes its "predefined uniforms declared per-shader" decision), [compliance suite](../../tools/shaderc/slang-compliance/README.md)

## Context

[ADR 0002](0002-slang-shader-library-composition.md) decided that a Slang shader declares the
predefined uniforms it uses in its own source (because Slang does not strip unused UBO members, a shared
library declaring *all* predefined uniforms would bloat every envelope). Porting example shaders exposed
how inconvenient — and error-prone — that is:

- **The layout is bgfx-internal.** bgfx lays predefined uniforms out in a fixed order (`bgfx_shader.sh`:
  `u_viewRect, u_viewTexel, u_view, u_invView, u_proj, u_invProj, u_viewProj, u_invViewProj, u_modelView,
  u_invModelView, u_modelViewProj, u_alphaRef4, u_model[]`). A shader that uses `u_modelView` +
  `u_modelViewProj` must declare them in that relative order to get the stock byte offsets
  (`u_modelView@0, u_modelViewProj@64`). An author cannot know this without reading bgfx internals; a
  natural declaration order produces the wrong offsets.
- **The envelope table order is glslang's live-enumeration order**, which is neither declaration nor
  offset order and is not reproducible from Slang reflection.

Both surfaced as `04-mesh` compliance failures on offsets *and* table order.

## Decision

**`shaderc` auto-declares the predefined uniforms a Slang shader references**, in the canonical
`bgfx_shader.sh` order, before compiling. Only the referenced names are injected (unused ones would
bloat the envelope). A shader simply *uses* `u_modelViewProj` — no declaration. A hand-written
declaration of a predefined name suppresses injection for that name (backward compatible), and
`--slang-no-predefined` disables the whole mechanism (falling back to ADR 0002's manual model). A
`#line 1` directive after the injected preamble keeps diagnostics pointing at the author's source.

`u_model` is provided as a **single `float4x4`**, not the bgfx `u_model[]` array. The stock compiler
strips a `u_model[0]` reference to a single matrix, and only a scalar `float4x4` decoration-matches it
(a Slang `float4x4 u_model[1]` produces a nested matrix-array decoration that does not). So Slang
authors write `mul(u_model, ...)` — cleaner than the bgfx `u_model[0]` idiom.

**The compliance suite compares the uniform table order-insensitively, and ignores loose-uniform byte
offsets.** Both the table order *and* each loose uniform's `$Globals` byte offset (`regIndex`) are
per-shader implementation details the runtime ignores: each renderer reads uniforms by name and stores
each one at its *own* offset (`renderer_vk.cpp` — `m_predefined[n].m_loc = regIndex`; user uniforms via
`createUniform` + a per-draw copy to the shader's own offset). A Slang shader with `u_norm_mtx@128` and a
stock shader with `u_norm_mtx@0` bind and run identically. The offset also legitimately *varies with the
stock source*: a `.sc` that declares a custom uniform **before** `#include common.sh` packs it at a lower
offset than the predefined block, the opposite of auto-provide's predefined-first injection — and it is
inconsistent across examples, so no single injection position matches all of them. Comparing loose
uniforms by identity (name/type/num/regcount) as a set — while still checking sampler/storage **bindings**
and the UBO **size** — tests real equivalence; pinning glslang's incidental order or byte layout would be
impossible to satisfy from Slang and meaningless at runtime. Matrix decorations are likewise compared by
their `(RowMajor|ColMajor, stride)` multiset (dropping the layout-dependent member index), which still
catches a transposed matrix.

## Consequences

- **Ports become mechanical**: write the shader logic, declare only *custom* uniforms; predefined ones
  and their bgfx-correct offsets come for free.
- **Backward compatible**: existing ports that declare predefined uniforms keep working.
- **Scope**: multi-bone skinning (`u_model[1]`, ...) is not covered — a shader that indexes past
  `u_model[0]` must declare the `u_model[]` array itself. The common single-model-matrix case is covered.
- **Trade-off accepted**: the compliance suite no longer pins uniform *order* or *loose-uniform byte
  offsets* to the stock compiler. This is deliberate and justified by the by-name/own-offset runtime
  contract above, not a relaxation of rigor — identity, sampler/storage bindings, UBO size, varyings,
  attributes and matrix row/col-major are all still checked.
