// 1-to-1 Slang port of examples/45-bokeh fs_bokeh_copy.sc.
// Stock includes parameters.sh but never reads u_params, so it is not declared here.
import bgfx_shader;

Texture2D    s_color        : register(t0);
SamplerState s_colorSampler : register(s0);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0;
	vec4 color = texture2D(s_color, s_colorSampler, texCoord);
	return color;
}
