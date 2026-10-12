// Slang port of examples/54-s2h/fs_s2h_scatter_display.sc.
import bgfx_shader;

Texture2D    s_scatterColor        : register(t0);
SamplerState s_scatterColorSampler : register(s0);

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return texture2D(s_scatterColor, s_scatterColorSampler, input.v_texcoord0);
}
