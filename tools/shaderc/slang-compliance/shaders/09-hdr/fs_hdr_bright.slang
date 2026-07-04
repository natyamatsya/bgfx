// 1-to-1 Slang port of examples/09-hdr fs_hdr_bright.sc.
// decodeRE8/decodeRGBE8 come from examples/common/shaderlib.sh (import shaderlib);
// reinhard2 comes from examples/09-hdr/common.sh (import common).
import bgfx_shader;
import shaderlib;
import common;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);
Texture2D    s_texLum          : register(t1);
SamplerState s_texLumSampler   : register(s1);

// The stock shader declares u_offset[16] but only reads [0..8], so glslang reflects
// u_offset with the active count 9 while still reserving the full [16] in the $Globals
// layout (u_tonemap lands at byte offset 256). Slang reflects the *declared* array
// extent, so u_offset is declared [9] to match the active count, and the reserved tail
// (elements [9..15], 7*vec4 = 112 bytes) is reproduced by an unused padding member so
// u_tonemap keeps its offset 256 and the UBO size stays 272.
struct OffsetTailPad { vec4 _unused[7]; };
vec4 u_offset[9];
OffsetTailPad _offsetTailPad;
vec4 u_tonemap;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	float lum = clamp(decodeRE8(texture2D(s_texLum, s_texLumSampler, input.v_texcoord0) ), 0.1, 0.7);

	vec3 rgb = vec3(0.0, 0.0, 0.0);
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[0].xy) );
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[1].xy) );
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[2].xy) );
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[3].xy) );
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[4].xy) );
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[5].xy) );
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[6].xy) );
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[7].xy) );
	rgb += decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[8].xy) );

	rgb *= 1.0/9.0;

	float middleGray = u_tonemap.x;
	float whiteSqr   = u_tonemap.y;
	float threshold  = u_tonemap.z;
	float offset     = u_tonemap.w;

	rgb = max(vec3_splat(0.0), rgb - threshold) * middleGray / (lum + 0.0001);
	rgb = reinhard2(rgb, whiteSqr);

	return toGamma(vec4(rgb, 1.0) );
}
