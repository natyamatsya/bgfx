// 1-to-1 Slang port of examples/09-hdr fs_hdr_lumavg.sc.
// decodeRE8/encodeRE8 come from examples/common/shaderlib.sh (import shaderlib).
import bgfx_shader;
import shaderlib;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

vec4 u_offset[16];

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	float sum;
	sum  = decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 0].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 1].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 2].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 3].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 4].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 5].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 6].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 7].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 8].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[ 9].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[10].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[11].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[12].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[13].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[14].xy) );
	sum += decodeRE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0+u_offset[15].xy) );
	float avg = sum/16.0;
	return encodeRE8(avg);
}
