// 1-to-1 Slang port of examples/09-hdr fs_hdr_lum.sc.
// decodeRGBE8/encodeRE8 come from examples/common/shaderlib.sh (import shaderlib).
// luma()/toGamma come from bgfx_shader.
import bgfx_shader;
import shaderlib;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

vec4 u_offset[9];

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	float delta = 0.0001;

	vec3 rgb0 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[0].xy) );
	vec3 rgb1 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[1].xy) );
	vec3 rgb2 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[2].xy) );
	vec3 rgb3 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[3].xy) );
	vec3 rgb4 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[4].xy) );
	vec3 rgb5 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[5].xy) );
	vec3 rgb6 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[6].xy) );
	vec3 rgb7 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[7].xy) );
	vec3 rgb8 = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[8].xy) );
	float avg = luma(rgb0).x
			  + luma(rgb1).x
			  + luma(rgb2).x
			  + luma(rgb3).x
			  + luma(rgb4).x
			  + luma(rgb5).x
			  + luma(rgb6).x
			  + luma(rgb7).x
			  + luma(rgb8).x
			  ;
	avg *= 1.0/9.0;

	return encodeRE8(avg);
}
