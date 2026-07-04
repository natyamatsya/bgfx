/*
* Copyright 2021 Richard Schubert. All rights reserved.
* License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
*
* AMD FidelityFX Super Resolution 1.0 (FSR)
* Slang port of examples/46-fsr/cs_fsr.h.
*
* Faithful 1-to-1 translation of the stock shared compute body. The stock file
* #includes the two AMD FidelityFX headers ffx_a.h / ffx_fsr1.h; those are pure
* C-preprocessor / macro headers (AF1/AH1 type macros, macro-generated helpers),
* so they cannot become `import` modules -- they are #included here exactly as the
* stock .sc does (co-located verbatim copies), which Slang's preprocessor supports.
* Only the bgfx glue (samplers/images, texture ops, entry point) is adapted to Slang.
*
* shaderc compiles the stock .sc with `-p spirv`, leaving BGFX_SHADER_LANGUAGE_GLSL == 0,
* so the stock takes the A_HLSL branch of the ffx headers. Slang is an HLSL dialect, so we
* likewise select A_HLSL.
*/

import bgfx_compute;
import bgfx_shader;

// EASU / BILINEAR use u_params[0..2]; RCAS only uses u_params[0]. glslang reflects (and
// reserves) the array at its used extent, so size the declaration to match per variant.
#if SAMPLE_RCAS
uniform vec4 u_params[1];
#else
uniform vec4 u_params[3];
#endif

#define ViewportSizeRcasAttenuation u_params[0]
#define SrcSize                     u_params[1]
#define DstSize                     u_params[2]

#define A_GPU 1
#define A_HLSL 1

#if SAMPLE_SLOW_FALLBACK
#	include "ffx_a.h"
	Texture2D    InputTexture        : register(t0);
	SamplerState InputTextureSampler : register(s0);
	[[vk::image_format("rgba32f")]] RWTexture2D<vec4> OutputTexture : register(u1);
#	if SAMPLE_EASU
		#define FSR_EASU_F 1
		AF4 FsrEasuRF(AF2 p) { AF4 res = InputTexture.GatherRed  (InputTextureSampler, p); return res; }
		AF4 FsrEasuGF(AF2 p) { AF4 res = InputTexture.GatherGreen(InputTextureSampler, p); return res; }
		AF4 FsrEasuBF(AF2 p) { AF4 res = InputTexture.GatherBlue (InputTextureSampler, p); return res; }
#	endif
#	if SAMPLE_RCAS
		#define FSR_RCAS_F
		AF4 FsrRcasLoadF(ASU2 p) { return InputTexture.Load(ASU3(ASU2(p), 0)); }
		void FsrRcasInputF(inout AF1 r, inout AF1 g, inout AF1 b) {}
#	endif
#else
#	define A_HALF
	// The stock A_HLSL A_HALF path uses HLSL minimum-precision types (min16float / min16uint /
	// min16int). Slang has no min-precision spellings, so alias them to the exact-width 16-bit
	// types it does provide -- keeping the stock (non-A_HLSL_6_2) code path verbatim.
	typedef float16_t  min16float;
	typedef float16_t2 min16float2;
	typedef float16_t3 min16float3;
	typedef float16_t4 min16float4;
	typedef uint16_t   min16uint;
	typedef uint16_t2  min16uint2;
	typedef uint16_t3  min16uint3;
	typedef uint16_t4  min16uint4;
	typedef int16_t    min16int;
	typedef int16_t2   min16int2;
	typedef int16_t3   min16int3;
	typedef int16_t4   min16int4;
#	include "ffx_a.h"
	Texture2D    InputTexture        : register(t0);
	SamplerState InputTextureSampler : register(s0);
	[[vk::image_format("rgba16f")]] RWTexture2D<vec4> OutputTexture : register(u1);
#	if SAMPLE_EASU
		#define FSR_EASU_H 1
		AH4 FsrEasuRH(AF2 p) { AH4 res = AH4(InputTexture.GatherRed  (InputTextureSampler, p)); return res; }
		AH4 FsrEasuGH(AF2 p) { AH4 res = AH4(InputTexture.GatherGreen(InputTextureSampler, p)); return res; }
		AH4 FsrEasuBH(AF2 p) { AH4 res = AH4(InputTexture.GatherBlue (InputTextureSampler, p)); return res; }
#	endif
#	if SAMPLE_RCAS
		#define FSR_RCAS_H
		AH4 FsrRcasLoadH(ASW2 p) { return AH4(InputTexture.Load(ASU3(ASU2(p), 0))); }
		void FsrRcasInputH(inout AH1 r,inout AH1 g,inout AH1 b){}
#	endif
#endif

#include "ffx_fsr1.h"

void CurrFilter(AU2 pos, AU4 Const0, AU4 Const1, AU4 Const2, AU4 Const3, AU4 Sample)
{
#if SAMPLE_BILINEAR
	AF2 pp = (AF2(pos) * AF2_AU2(Const0.xy) + AF2_AU2(Const0.zw)) * AF2_AU2(Const1.xy) + AF2(0.5, -0.5) * AF2_AU2(Const1.zw);
	imageStore(OutputTexture, ASU2(pos), texture2DLod(InputTexture, InputTextureSampler, pp, 0.0));
#endif

#if SAMPLE_EASU
#	if SAMPLE_SLOW_FALLBACK
		AF3 c;
		FsrEasuF(c, pos, Const0, Const1, Const2, Const3);
		if( Sample.x == 1 )
			c *= c;
		imageStore(OutputTexture, ASU2(pos), AF4(c, 1));
#	else
		AH3 c;
		FsrEasuH(c, pos, Const0, Const1, Const2, Const3);
		if( Sample.x == 1 )
			c *= c;
		imageStore(OutputTexture, ASU2(pos), vec4(AH4(c, 1)));
#	endif
#endif

#if SAMPLE_RCAS
#	if SAMPLE_SLOW_FALLBACK
		AF3 c;
		FsrRcasF(c.r, c.g, c.b, pos, Const0);
		if( Sample.x == 1 )
			c *= c;
		imageStore(OutputTexture, ASU2(pos), AF4(c, 1));
#	else
		AH3 c;
		FsrRcasH(c.r, c.g, c.b, pos, Const0);
		if( Sample.x == 1 )
			c *= c;
		imageStore(OutputTexture, ASU2(pos), vec4(AH4(c, 1)));
#	endif
#endif
}

[shader("compute")]
[numthreads(64, 1, 1)]
void computeMain(uint3 gl_LocalInvocationID : SV_GroupThreadID, uint3 gl_WorkGroupID : SV_GroupID)
{
	AU4 Const0, Const1, Const2, Const3, Sample;

	// We compute these constants on GPU because bgfx does not support uniform type uint.
#if SAMPLE_EASU || SAMPLE_BILINEAR
	FsrEasuCon(Const0, Const1, Const2, Const3,
		ViewportSizeRcasAttenuation.x, ViewportSizeRcasAttenuation.y,  // Viewport size (top left aligned) in the input image which is to be scaled.
		SrcSize.x, SrcSize.y,  // The size of the input image.
		DstSize.x, DstSize.y); // The output resolution.
	Sample.x = 0; // no HDR output
#endif // SAMPLE_EASU || SAMPLE_BILINEAR

#if SAMPLE_RCAS
	FsrRcasCon(Const0, ViewportSizeRcasAttenuation.z);
	Sample.x = 0;  // no HDR output
#endif // SAMPLE_RCAS

	// Do remapping of local xy in workgroup for a more PS-like swizzle pattern.
	AU2 gxy = ARmp8x8(gl_LocalInvocationID.x) + AU2(gl_WorkGroupID.x << 4u, gl_WorkGroupID.y << 4u);
	CurrFilter(gxy, Const0, Const1, Const2, Const3, Sample);
	gxy.x += 8u;
	CurrFilter(gxy, Const0, Const1, Const2, Const3, Sample);
	gxy.y += 8u;
	CurrFilter(gxy, Const0, Const1, Const2, Const3, Sample);
	gxy.x -= 8u;
	CurrFilter(gxy, Const0, Const1, Const2, Const3, Sample);
}
