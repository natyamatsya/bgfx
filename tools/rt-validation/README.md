# rt-validation — headless acceleration-structure runtime tests

Headless harnesses that exercise the bgfx ray-tracing runtime end to end
(`createBlas` / `createTlas` / `updateTlas` / `setAccelerationStructure` + ray-query
dispatch) without a window, on any backend reporting `BGFX_CAPS_RAY_TRACING`.

- `rt_smoke.cpp` — four phases, exit 0 = all pass: (1) triangle BLAS/TLAS hit test
  (expects 4096/4096 hit pixels); (2) `updateTlas` rotation test (rotates the instance
  90°; expects 0/4096); (3) multi-geometry BLAS (a hit on geometry index 1);
  (4) refit: a compute shader (`cs_rt_deform.slang`) moves the vertices of a
  `BGFX_BUFFER_COMPUTE_WRITE` vertex buffer off the ray, `updateBlas` refits in place
  (expects a miss).
- `rt_cornellbox.cpp` — the full 52-cornellbox pipeline (tracer + temporal reprojection +
  a-trous denoiser + ReSTIR stage) writing PPM images for cross-backend comparison. Uses
  the example's compiled shaders from `examples/runtime/shaders/<target>/`.
- `cs_rt_smoke.slang` — the smoke test's ray-query shader; compile with shaderc for the
  target backend (`-p metal --platform osx` / `-p spirv --platform linux`).
- `rt_pipeline_smoke.cpp` — the ray-tracing **pipeline** smoke test
  (`bgfx::createRtProgram`, `BGFX_CAPS_RAY_TRACING_PIPELINE`): raygen + TWO miss shaders +
  a triangle hit group, traced via `bgfx::dispatch` (ray-grid dimensions in rays). The
  closest-hit stage reads a chit-only material buffer, shares the acceleration-structure
  binding with raygen, and fires a secondary ray (recursion depth 2) routed to miss
  index 1 — full white only if every v2 feature works. Skips cleanly where the cap is
  absent (e.g. Metal). Stage shaders: `rt_pipe_{rg,miss,miss2,chit}.slang` compiled with
  `--type raygeneration|miss|closesthit -p spirv`. Phase 2 adds any-hit + callable
  coverage: two overlapping instances traced with `RAY_FLAG_FORCE_NON_OPAQUE` (bgfx BLAS
  geometry is built opaque, which skips any-hit otherwise); the any-hit stage rejects the
  front instance and a callable adds a distinct value (`rt_pipe_{rg2,ahit,chit2,call}.slang`).
  Phase 3 covers procedural intersection: a sphere inside an AABB BLAS
  (`bgfx::createBlasAabbs`); the intersection shader reports the analytic entry point and
  the closest-hit stage validates the reported t (`rt_pipe_{isect,chit3}.slang`).
- `metal_rt_host.h` — shared host helpers (MSL loading, stage-function lookup,
  AS building, the software-SBT layout) used by the p1/p4 hosts; p0/p3 predate it
  and stay self-contained.
- `p5/rt_p5_transforms.slang` — the transforms-phase module (ObjectToWorld/
  WorldToObject/ObjectRay* under a translated instance); runs on the p4 host.
- `metal_rt_pipeline_p{0,1,3,4}.cpp` + `p0/ p1/ p3/ p4/` — the staged on-device
  proofs of the Slang-native Metal RT pipeline (compiler side: the Slang fork's
  `metal-rt-impl` branch, `github.com/natyamatsya/slang`): P0 raygen/miss/chit +
  runtime contract, P1 anyhit/intersection function tables, P3 recursion + the
  `slang_RTGlobals` argument buffer, P4 world-space semantics under instance
  transforms. Compile the stage modules with that fork's `slangc -target metal`.
- `metal_rt_pipeline_spike.cpp` — standalone (raw metal-cpp, no bgfx) on-device proof
  that the RT pipeline model maps onto Metal visible-function + intersection-function
  tables; see `METAL_RT_PIPELINE.md`. Build:
  `clang++ -std=c++17 -I 3rdparty tools/rt-validation/metal_rt_pipeline_spike.cpp
  -framework Metal -framework Foundation -framework QuartzCore -o mtl_spike`

## Metal (macOS host)

    clang++ -std=c++17 -I ../../include rt_smoke.cpp \
        ../../.build/osx-arm64/bin/lib{bgfx,bimg,bx}Debug.a \
        -framework Metal -framework Foundation -framework QuartzCore -framework Cocoa \
        -framework IOKit -framework CoreFoundation -framework CoreMedia \
        -framework VideoToolbox -framework CoreVideo -o rt_smoke
    ./rt_smoke cs_rt_smoke_metal.bin cs_rt_deform_metal.bin

## Vulkan without RT hardware: lavapipe (Mesa software Vulkan)

Mesa's lavapipe implements `VK_KHR_ray_query` / `VK_KHR_acceleration_structure` (and the
ray-tracing pipeline) on the CPU — Mesa >= 24.1; verified with Mesa 25.0 on Ubuntu 25.04.
This validates the entire Vulkan backend on machines with no RT GPU (and in CI).

On macOS with Apple's container CLI (arm64-native; generate the makefiles on the host
because the bundled Linux genie binary is x86_64 — and strip `-m64`, which aarch64 gcc
rejects):

    ../../../bx/tools/bin/darwin/genie --gcc=linux-arm-gcc gmake
    sed -i '' 's/ -m64//g' ../../.build/projects/gmake-linux-arm-gcc/*.make
    container system start
    container run -d --name lava --cpus 8 --memory 8g \
        -v $(dirname $(dirname $PWD)):/work ubuntu:25.04 sleep infinity
    container exec lava bash -c 'apt-get update -qq && apt-get install -y -qq \
        build-essential mesa-vulkan-drivers vulkan-tools libgl1-mesa-dev libx11-dev'
    container exec lava make -C /work/bgfx/.build/projects/gmake-linux-arm-gcc \
        bgfx bimg bimg_decode config=release64 -j8
    container exec lava bash -c 'cd /work/bgfx/tools/rt-validation && \
        g++ -std=c++20 -DBX_CONFIG_DEBUG=0 -I ../../include -I ../../../bx/include \
        rt_smoke.cpp ../../.build/linux32_arm_gcc/bin/lib{bgfx,bimg,bimg_decode,bx}Release.a \
        -lGL -lX11 -ldl -lpthread -lrt -o rt_smoke && \
        ./rt_smoke cs_rt_smoke_spirv.bin cs_rt_deform_spirv.bin'

## Cross-backend image comparison

Run `rt_cornellbox` on both backends with the same arguments and diff the PPMs; the
backends are expected to agree to Monte Carlo float divergence (measured: mean |delta|
0.12/255, <0.2% of samples off by more than 4/255).

Provenance: this rig found a real bug on first contact — the Vulkan RT extension rows were
declared detect-only (`m_initialize = false`), which `updateExtension()` never matches, so
`BGFX_CAPS_RAY_TRACING` could never turn on for any Vulkan driver.
