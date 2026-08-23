# Slang (vendored)

[Slang](https://github.com/shader-slang/slang) shader language support for `shaderc`.

Only the public API **headers** and a prebuilt **`libslang`** shared library are vendored — Slang is
**not** built from source and **not** statically linked. `shaderc` loads `libslang` dynamically at
runtime (`bx::dlopen`), the same way it loads DXC (`dxcompiler`). The backend is optional, gated by
`SHADERC_CONFIG_HAS_SLANG` (`__has_include(<slang.h>)`).

## Pinned version

- **Base version:** `2026.16` (`SLANG_VERSION_NUMERIC`)
- **Build:** `2026.16-28-g1e1c5bad8` (`SLANG_TAG_VERSION`)
- **Source:** the [`natyamatsya/slang`](https://github.com/natyamatsya/slang) fork, branch
  `metal-rt-impl`, rebased onto upstream Slang `2026.16`. The headers come from that branch, not
  from an official release tarball, because the native Metal RT path needs the fork's compiler
  changes (the `MetalRT*` entries in `CompilerOptionName`).
- **License:** Apache-2.0 WITH LLVM-exception (see `LICENSE`)

The `include/` headers and the loaded `libslang` **must** be the same Slang version.
`SLANG_API_VERSION` is validated by `slang_createGlobalSession`, but it is far too coarse to catch
this: it has been `0` across both versions. The real hazard is that `CompilerOptionName` is a
*value-assigned* enum, so upstream inserting options renumbers everything after them — `2026.14.1`
added `SeparateDebugInfoOutput = 156` / `DebugInfoIncludeSource = 157`, which pushed the fork's
options up by two (`MetalRTGlobalsSlots` went `159` → `161`). A mismatched pair therefore compiles
and links fine and then silently applies the wrong options. The `2026.16` bump did *not* renumber --
all four `MetalRT*` values are unchanged -- but that is luck, not a guarantee: check them on every
bump, because nothing but this check stands between a renumber and silently wrong codegen.

`shaderc` guards against this at runtime: `checkSlangVersion()` in `tools/shaderc/shaderc_slang.cpp`
compares `IGlobalSession::getBuildTagString()` against `SLANG_VERSION_NUMERIC` from these headers and
fails with a named-versions error on skew. Only the numeric version is compared, because a stock
upstream release reports `2026.16` while the fork build reports `2026.16-28-g1e1c5bad8` and both
are supported — see the platform note under *Vendored contents*.

## Vendored contents

- `include/` — the self-contained public API header closure:
  `slang.h`, `slang-com-ptr.h`, `slang-com-helper.h`, `slang-deprecated.h`,
  `slang-image-format-defs.h`, `slang-tag-version.h`.
- `../../tools/bin/darwin/libslang.dylib` — the prebuilt `libslang-compiler` shared library from
  the `2026.16-28-g1e1c5bad8` fork build (macOS arm64), flattened to a single file. The whole
  `tools/bin/darwin/` directory is otherwise `*`-gitignored, so that one file is explicitly
  un-ignored (`!libslang.dylib`).

The macOS `libslang-compiler` dylib links only `libc++`/`libSystem`; the LLVM
(`libslang-llvm`, ~107 MB) and glslang (`libslang-glslang`) companion libraries are **not** vendored
because the direct-SPIR-V code path does not need them. If a future target (CPU/host-callable, or
legacy `-emit-spirv-via-glsl`) is added, the corresponding companion must be added alongside.

### Windows

No Slang binary is committed for Windows. `tools/bin/windows/.gitignore` un-ignores `slang.dll` in
anticipation of one, but the working setup is to drop the **stock upstream release** next to
`shaderc*.exe` in `.build/win64_vs2022/bin/` (`slang.dll` plus `slang-compiler`, `slang-glslang`,
`slang-glsl-module`, `slang-llvm`, `slang-rt`, `gfx`), taken from
`slang-<ver>-windows-x86_64.zip`. A stock build is sufficient here because Windows only drives the
SPIR-V and DXIL targets, and the Metal-target route goes through SPIRV-Cross — none of them pass the
fork's `MetalRT*` options, which are the only reason the fork build is needed. The version must still
match these headers or `checkSlangVersion()` rejects it.

## Updating

The compiler is built from the `../slang` fork checkout (sibling of this repo). To re-vendor after
changing/rebasing that fork:

1. Build it Release **(macOS only)**: `cd ../slang && cmake --preset default && cmake --build --preset release --target slang`.

   **Drop the cached version first when re-vendoring in an existing build tree.**
   `SLANG_VERSION_FULL` / `SLANG_VERSION_NUMERIC` are `CACHE STRING`s, so a warm `build/` keeps the
   version it was first configured with: the rebuild picks up the new sources but stamps the old
   `SLANG_TAG_VERSION` into the dylib, which `checkSlangVersion()` then rejects against these
   headers. Force a re-`describe` with
   `cmake -S . -B build -U SLANG_VERSION_FULL -U SLANG_VERSION_NUMERIC` (look for
   `-- Using version from git describe: v<new tag>`) before building. The output filename is the
   tell — `libslang-compiler.0.<ver>.dylib` must carry the version you expect.
2. Replace the dylib **(macOS only)**: `cp -L ../slang/build/Release/lib/libslang-compiler.0.<ver>.dylib tools/bin/darwin/libslang.dylib`.
3. Replace the headers: the source headers (`slang.h`, `slang-com-ptr.h`, `slang-com-helper.h`,
   `slang-deprecated.h`, `slang-image-format-defs.h`) from `../slang/include/` on the fork branch
   being vendored — e.g. `git show metal-rt-impl:include/slang.h` — and the generated
   `slang-tag-version.h` from `../slang/build/Release/include/`.

   Steps 1–3 need no build if you only want the headers: `slang-tag-version.h` is
   `slang-tag-version.h.in` filled from `git describe`, so it can be written by hand. `cmake/GitVersion.cmake`
   runs `git describe --tags --match 'v20[2-9][0-9].[0-9]*'` and splits it with `^v(([0-9]+(\.[0-9]+)*).*)`
   — group 1 is `SLANG_TAG_VERSION`, group 2 is `SLANG_VERSION_NUMERIC`. That is how the `2026.14.1`
   header bump was done from a Windows host.
4. Refresh the Windows dlls in `.build/win64_vs2022/bin/` from the matching stock release (see
   *Windows* above), or `checkSlangVersion()` will reject the pair.
5. Update the version block above to match `slang-tag-version.h`.
6. Revalidate. `tools/shaderc/slang-compliance/run.py --target spirv` and `--target metal`, plus
   `rt_stages.py`, recompile every shader through the new compiler and are the real gate. On Windows,
   also recompile the `tools/rt-validation` shaders to DXIL and run `rt_smoke` / `rt_pipeline_smoke`
   against the fresh blobs — that covers codegen end-to-end on hardware. Regenerate the committed
   Slang shader binaries if codegen changed.

For a future non-fork bump, the equivalent is downloading `slang-<tag>-macos-aarch64.tar.gz` from the
upstream release and taking `include/` + the dylib from it.
