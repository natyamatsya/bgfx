// 1-to-1 Slang port of examples/23-vectordisplay fs_vectordisplay_fb.sc.
import bgfx_shader;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

vec4 u_params;
#define u_blur_scale    u_params.xy
#define u_compose_mult  u_params.z
#define u_compose_alpha u_params.w

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_color0    : COLOR0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 texColor = texture2D(s_texColor, s_texColorSampler, input.v_texcoord0.xy);
	return input.v_color0 * texColor * vec4(1.0, 1.0, 1.0, u_compose_alpha);
}
