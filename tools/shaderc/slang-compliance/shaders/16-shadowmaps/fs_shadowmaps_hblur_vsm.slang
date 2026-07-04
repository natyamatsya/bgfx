// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_hblur_vsm.sc
import bgfx_shader;
import common; // blur9VSM

Texture2D    s_shadowMap0        : register(t4);
SamplerState s_shadowMap0Sampler : register(s4);

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
	vec4 v_texcoord2 : TEXCOORD2;
	vec4 v_texcoord3 : TEXCOORD3;
	vec4 v_texcoord4 : TEXCOORD4;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return blur9VSM(s_shadowMap0, s_shadowMap0Sampler
						, input.v_texcoord0
						, input.v_texcoord1
						, input.v_texcoord2
						, input.v_texcoord3
						, input.v_texcoord4
						);
}
