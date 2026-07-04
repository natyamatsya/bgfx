# Slang (vendored)

[Slang](https://github.com/shader-slang/slang) shader language support for `shaderc`.

Only the public API **headers** and a prebuilt **`libslang`** shared library are vendored — Slang is
**not** built from source and **not** statically linked. `shaderc` loads `libslang` dynamically at
runtime (`bx::dlopen`), the same way it loads DXC (`dxcompiler`). The backend is optional, gated by
`SHADERC_CONFIG_HAS_SLANG` (`__has_include(<slang.h>)`).

## Pinned version

- **Base version:** `2026.12.2` (`SLANG_VERSION_NUMERIC`)
- **Build:** `2026.12.2-59-ge47241c82` (`SLANG_TAG_VERSION`)
- **Source:** the [`natyamatsya/slang`](https://github.com/natyamatsya/slang) fork (Metal ray-tracing
  branches), rebased onto upstream Slang `2026.12.2`. Built locally from `../slang` (Release), not
  from an official release tarball, because the native Metal RT path needs the fork's compiler changes.
- **License:** Apache-2.0 WITH LLVM-exception (see `LICENSE`)

The `include/` headers and the prebuilt library **must** come from the same build —
`SLANG_API_VERSION` is validated by `slang_createGlobalSession`.

## Vendored contents

- `include/` — the self-contained public API header closure:
  `slang.h`, `slang-com-ptr.h`, `slang-com-helper.h`, `slang-deprecated.h`,
  `slang-image-format-defs.h`, `slang-tag-version.h`.
- `../../tools/bin/darwin/libslang.dylib` — the prebuilt `libslang-compiler` shared library from
  v2026.12.2 (macOS arm64), flattened to a single file. The whole `tools/bin/darwin/` directory is
  otherwise `*`-gitignored, so that one file is explicitly un-ignored (`!libslang.dylib`).

The macOS `libslang-compiler` dylib links only `libc++`/`libSystem`; the LLVM
(`libslang-llvm`, ~107 MB) and glslang (`libslang-glslang`) companion libraries are **not** vendored
because the direct-SPIR-V code path does not need them. If a future target (CPU/host-callable, or
legacy `-emit-spirv-via-glsl`) is added, the corresponding companion must be added alongside.

## Updating

The compiler is built from the `../slang` fork checkout (sibling of this repo). To re-vendor after
changing/rebasing that fork:

1. Build it Release: `cd ../slang && cmake --preset default && cmake --build --preset release --target slang`.
2. Replace the dylib: `cp -L ../slang/build/Release/lib/libslang-compiler.0.<ver>.dylib tools/bin/darwin/libslang.dylib`.
3. Replace the headers: the source headers (`slang.h`, `slang-com-ptr.h`, `slang-com-helper.h`,
   `slang-deprecated.h`, `slang-image-format-defs.h`) from `../slang/include/`, and the generated
   `slang-tag-version.h` from `../slang/build/Release/include/`.
4. Update the version block above to match `slang-tag-version.h`.
5. Re-run the `shaderc_slang` smoke test / byte-golden verification (and regenerate the example
   Slang shader binaries if the compiler's codegen changed).

For a future non-fork bump, the equivalent is downloading `slang-<tag>-macos-aarch64.tar.gz` from the
upstream release and taking `include/` + the dylib from it.
