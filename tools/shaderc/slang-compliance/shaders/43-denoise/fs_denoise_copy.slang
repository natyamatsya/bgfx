// 1-to-1 Slang port of examples/43-denoise fs_denoise_copy.sc.
// parameters.sh is included but no u_params macro is referenced, so u_params is
// dead-stripped and not declared.
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
