// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_texture.sc
import bgfx_shader;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return texture2D(s_texColor, s_texColorSampler, input.v_texcoord0);
}
