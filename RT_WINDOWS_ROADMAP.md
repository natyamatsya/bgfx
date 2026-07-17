# bgfx × Ray Tracing — Windows Roadmap (Vulkan port + D3D12/DXR backend)

> Status: **draft / planning.** Companion to `RT_ROADMAP.md` (the completed VK+Metal
> runtime) and `METAL_RT_PIPELINE.md`. Milestones with essential steps; depth arrives
> per-milestone when work starts.
>
> **Gap-check vs. the post-rebase tree (2026-07-18).** After rebasing the fork onto current
> upstream bgfx and re-vendoring Slang, this roadmap was verified against the code. Net:
> M1 (DXIL) holds; M2/M3 remain the real work, with the D3D12 API + caps detection already
> stubbed in. Three deltas fold into the milestones below:
> - **Resolved:** the M1 libslang-version caveat — the fork now vendors **libslang 2026.12.2**,
>   and the SPIR-V compliance suite (604/604) proves `VulkanBindShiftAll` works. Only the
>   loader-side version check remains a follow-up.
> - **Correction:** the D3D12 RT caps detection that "landed" is a **Tier-1_0 placeholder**
>   (`m_rayTracingSupport = RaytracingTier >= TIER_1_0` → `BGFX_CAPS_RAY_TRACING`). Inline ray
>   query needs **Tier 1_1**; M2 must split the gates (see M2). There is no
>   `BGFX_CAPS_RAY_TRACING_PIPELINE` gate for D3D12 yet.
> - **Validation gap:** the routine compliance suite targets **SPIR-V + Metal only** — DXIL is
>   not exercised, so M1's output is unverified against libslang 2026.12.2 (see M1 exit).

## 1. Goal and starting position

Bring the acceleration-structure runtime and the ray-tracing pipeline
(`createBlas`/`createTlas`/`updateBlas`/`updateTlas`, `setAccelerationStructure`,
`createRtProgram` + dispatch-as-trace, both caps bits) to Windows: the **Vulkan backend
as a port** (the code is OS-agnostic) and a **new D3D12/DXR implementation**.

What transfers with zero design work — worth stating so the plan stays honest about
where the real effort is:

- **The public API and IDL layer** — backend-agnostic by construction.
- **The test corpus** — `rt_smoke` (4 phases), `rt_pipeline_smoke` (3 phases), the P0
  referee, the Cornell Box cross-checks: all backend-agnostic harnesses keyed off caps.
- **The Slang front-end** — all six RT stages compile target-independently; envelopes
  already carry them.
- **The SBT/record-index design** — DXR is the *origin* of the model the VK backend
  implements (hit-group formula, region bases, per-instance contributions); D3D12 is a
  homecoming, not a translation.
- **The referee methodology** — and this is the load-bearing observation: **WARP
  (Microsoft's software D3D12 adapter) supports DXR.** WARP is to D3D12 what lavapipe
  is to Vulkan: a CPU-only, CI-able reference implementation. The entire
  build-headless/validate-cross-backend workflow ports intact, GPU-free.

The two genuinely new problems:

1. **DXIL.** bgfx's D3D12 backend consumes DXBC (fxc, SM 5.x). DXR requires SM ≥ 6.3,
   i.e. **DXIL from dxc** — a shader-blob format the runtime has never loaded. The
   clean answer is the asset we already built: **Slang emits DXIL natively**
   (`SLANG_DXIL`), so shaderc's Slang front-end grows a third target beside SPIR-V and
   MSL, and the frozen-envelope discipline holds (new blob format inside the same
   envelope, exactly like the Metal path). fxc/DXBC stays untouched for classic
   graphics.
2. **Local development without a Windows dev machine.** dxc is cross-platform, so DXIL
   envelopes compile on this macOS host. Runtime validation runs on WARP — in a
   Windows-on-ARM VM locally and/or stock GitHub Actions Windows runners in CI. One
   caveat to resolve early: **DXIL signing** (`dxil.dll` is Windows-only; unsigned DXIL
   needs the experimental-shader-models feature, which WARP/dev-mode accepts — fine for
   the fork and CI; retail signing happens on a Windows builder later).

## 2. Milestones

### M0 — Windows build + Vulkan port validation
*The fork builds and the existing runtime runs on Windows; CI skeleton exists.*

- genie vs2022 projects for the fork (libbgfx, shaderc with the Slang front-end —
  libslang.dylib → slang.dll loading), examples.
- Run the full existing suite on Windows/Vulkan: real RT hardware if available
  (this doubles as the long-standing "real-hardware pass" from `RT_ROADMAP.md`),
  plus **lavapipe via mesa-dist-win** for the deterministic CPU referee.
- GitHub Actions matrix seed: windows runner building + running the VK smoke tests on
  lavapipe. (The linux-arm container rig stays the primary referee.)
- Exit: `rt_smoke` 4/4 and `rt_pipeline_smoke` 3/3 green on Windows/VK.
- **Status (scaffolding started, 2026-07-18, `experimental/rt-windows`):**
  - ✅ `genie vs2022` generates the fork cleanly (79/79 projects; `shaderc`, `bgfx`,
    combined examples all present) — no fork-specific project breakage. The upstream
    `msvc` CI job already builds the fork on Windows via vs2022 + msbuild.
  - ✅ Slang front-end wired for Windows: `shaderc_slang.cpp` already selects `slang.dll`
    per platform; `tools/bin/windows/.gitignore` now un-ignores `!slang.dll`; and a
    **Slang compliance (SPIR-V)** step added to the `msvc` job (mirrors the osx job —
    fetches `slang.dll`, runs `run.py --target spirv`). *TODO:* pin the `slang.dll`
    version to the vendored headers and move to a fork Windows build.
  - ✅ RT validation tools wired as **genie projects** (`scripts/rt-validation.lua`,
    dofile'd under `--with-tools`): `rt_smoke`, `rt_pipeline_smoke`,
    `rt_pipeline_p0_referee`, `rt_pipeline_cornellbox`, `rt_bench`. They no longer build
    ad-hoc — all five compile + link (verified on macOS) and now build in the branch's
    `msvc`/`linux`/`osx` CI, which doubles as a cross-platform compile check. (Platform
    frameworks/libs are declared in the project since bgfx's don't propagate to
    consumers.)
  - ⬜ **Core remaining M0 — run them on lavapipe.** A windows/lavapipe
    (`mesa-dist-win` software VK) CI job that compiles the `.bin` shaders and runs
    `rt_smoke` 4/4 + `rt_pipeline_smoke` 3/3. Needs a real-runner shakedown (and the
    tools' shader inputs generated for SPIR-V).

### M1 — shaderc DXIL target ✅ (compiler side landed; envelope consumed in M2)
*Slang → DXIL envelopes for compute and all six RT stages, compiled from any host OS.*

- Wire `SLANG_DXIL` beside SPIR-V/Metal in `shaderc_slang.cpp`; dxcompiler integration;
  decide the signing story (unsigned + experimental feature for dev/CI).
- Binding-convention design, the DXIL analog of the `kSpirvBindShift` work: bgfx stages
  ↔ HLSL register/space assignments ↔ the D3D12 backend's root-signature layout. This
  is the one design-heavy item in the milestone.
- Envelope: DXIL code blob + the same reflection tables; runtime selects by blob format.
- Exit: the whole RT test-shader corpus emits DXIL envelopes from the macOS host,
  spot-validated with dxc disassembly. NOTE (post-rebase gap-check): the routine
  compliance suite (`run.py`) targets SPIR-V + Metal only, so DXIL is **not** continuously
  checked — re-validate DXIL output against the newly-vendored libslang 2026.12.2 and add a
  DXIL golden to the referee (long-term home is the M4 triple-referee).
- **Status**: landed on `experimental/shaderc-dxil`. All six RT stages + ray-query
  compute + the Cornell Box tracer emit DXIL envelopes from macOS (`-p s_6_5
  --platform windows`); dxc disassembly confirms the pass-through register convention
  (`scene t0`, `s_target u1`, ... — the identity mapping IS the D3D convention, no
  shift design needed); envelope reflection carries raw registers + cbuffer byte
  offsets. Zero drift on the SPIR-V/Metal paths (byte-identical output vs the
  unpatched compiler, same libslang). Graphics stages (v/f) are cleanly rejected until
  the D3D12 backend work defines their conventions. Found along the way: libslang
  2025.23 silently ignored `VulkanBindShiftAll` (wrong SPIR-V bindings, no error), so the
  Slang front-end needs libslang ≥ 2026.x. **Resolved (2026-07-18):** the fork now vendors
  **libslang 2026.12.2** and the SPIR-V compliance suite (604/604) confirms the bind-shift;
  only the loader-side version check remains a hardening follow-up.

### M2 — D3D12 acceleration structures + inline ray query
*The `RT_ROADMAP.md` phase-3/4 equivalent for D3D12.*

- `AccelerationStructureD3D12`: BLAS (triangles + AABBs), refit
  (`PERFORM_UPDATE`), TLAS + `updateTlas` (instance descs are 3×4 row-major — same
  mapping as VK's `VkTransformMatrixKHR`, reuse it), UAV barriers, scratch sizing.
  The backend overrides (`createBlas`/`createBlasAabbs`/`updateBlas`/`createTlas`/
  `updateTlas`/`createRtProgram`/`destroyAccelerationStructure`) already exist as empty
  `BX_UNUSED` stubs in `renderer_d3d12.cpp` — M2/M3 fills them in, it does not add the API.
- DXIL compute PSO path in the runtime (SM 6.5 `RayQuery` requires it) + AS binding as
  the raytracing SRV; caps: **fix the gating** — the feature-config phase landed only a
  Tier-1_0 *placeholder* (`m_rayTracingSupport = RaytracingTier >= TIER_1_0` →
  `BGFX_CAPS_RAY_TRACING`), but inline ray query requires **Tier 1_1**. M2 must gate
  `BGFX_CAPS_RAY_TRACING` on `RaytracingTier ≥ 1_1`, and M3 add
  `BGFX_CAPS_RAY_TRACING_PIPELINE` at `≥ 1_0` (no such gate exists yet).
- Exit: `rt_smoke` 4/4 on **WARP**; Cornell Box compute + ray-query stages render;
  cross-backend image check vs lavapipe.

### M3 — D3D12 ray-tracing pipeline
*`createRtProgram` on its native platform.*

- State objects: one DXIL library per stage envelope, hit groups (chit/anyhit/
  intersection — all DXR-native), `maxRecursionDepth` 2, callables.
- SBT: `GetShaderIdentifier` (32-byte handles), region layout identical in spirit to
  the VK implementation; `DispatchRays` from the dispatch path.
- Caps: `BGFX_CAPS_RAY_TRACING_PIPELINE` from Tier ≥ 1_0 (pipeline) — Metal keeps its
  own gate.
- Exit: `rt_pipeline_smoke` 3/3 and the P0 referee on WARP.

### M4 — Triple-referee, example, consolidation
*The finish line: one Slang source, three backends, one image.*

- Cornell Box stage-5 image cross-check: **lavapipe vs WARP vs Metal** (SPIR-V vs DXIL
  vs MSL from the same sources) — the compliance argument for upstreaming in one
  screenshot-diff.
- 52-cornellbox runs on D3D12 end to end; docs (`RT_ROADMAP.md` links, `docs/`),
  CI matrix final (linux-arm container + windows WARP runner).
- jj series consolidation for the D3D12 stack, mirroring the VK/Metal series shape.

## 3. Risks / open questions (tracked, not blocking the plan)

1. **DXIL signing off-Windows** — unsigned+experimental is believed sufficient for WARP
   and dev-mode hardware; confirm in M1, and confirm GitHub runners allow the
   experimental feature (they run with developer mode configurable).
2. **WARP DXR coverage/versions** — needs a recent Agility SDK; pin the version in M0.
   If a WARP gap appears (e.g. callables), vkd3d-proton-on-lavapipe is the fallback
   referee for that feature.
3. **Root-signature vs Slang DXIL layout** — the M1 binding-convention design must land
   before M2 code; it is the analog of (and should crib from) the SPIR-V shift design.
4. **Windows-on-ARM local VM** — WARP is architecture-native on ARM64 Windows; if VM
   friction is high, CI-only validation is acceptable (the suite is fast and
   deterministic).
5. **bgfx upstream posture** — D3D12+DXIL has long been requested upstream; keeping the
   DXIL path Slang-front-end-only preserves the zero-envelope-change discipline that
   the Slang and RT series already argue from.
