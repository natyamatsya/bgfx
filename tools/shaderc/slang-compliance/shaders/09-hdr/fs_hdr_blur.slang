// 1-to-1 Slang port of examples/09-hdr fs_hdr_blur.sc.
// blur9() comes from examples/09-hdr/common.sh (a local, non-shaderlib helper): ported
// once to the co-located common.sh.slang and imported here.
import bgfx_shader;
import common;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
	vec4 v_texcoord2 : TEXCOORD2;
	vec4 v_texcoord3 : TEXCOORD3;
	vec4 v_texcoord4 : TEXCOORD4;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return blur9(s_texColor, s_texColorSampler, input.v_texcoord0, input.v_texcoord1, input.v_texcoord2, input.v_texcoord3, input.v_texcoord4);
}
