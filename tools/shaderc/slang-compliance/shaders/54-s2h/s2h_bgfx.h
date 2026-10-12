// Slang adapter for examples/common/s2h/s2h_bgfx.sh -- the S2H library's bgfx shaderc
// compatibility layer. #include'd, not imported: it defines the macros s2h.hlsl needs, and
// a macro does not cross an `import`. The EA library itself is included unchanged (it
// already guards its GLSL shims with #ifndef __SLANG__), so nothing here forks it.
#ifndef S2H_BGFX_INCLUDE
#define S2H_BGFX_INCLUDE

#define S2H_BGFX 1
#define S2H_LOOP

// shaderc's generated HLSL does not permit asfloat() in a global const initializer.
#define S2H_FLT_MAX 1.0e30f

#include "s2h/s2h_glsl.hlsl"

// S2H uses a top-left pixel origin, which is already the convention on every target the
// Slang front-end drives (SPIR-V/Vulkan, DXIL and Metal), so no flip is needed -- the stock
// adapter's mix() against bgfx_ndc.z is the BGFX_SHADER_LANGUAGE_GLSL branch only.
float2 s2h_getPixelCoord(float2 _fragmentCoord)
{
	return _fragmentCoord;
}

#endif // S2H_BGFX_INCLUDE
