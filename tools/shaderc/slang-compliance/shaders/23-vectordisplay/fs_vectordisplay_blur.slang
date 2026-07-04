// 1-to-1 Slang port of examples/23-vectordisplay fs_vectordisplay_blur.sc.
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
	vec4 color;
	color  = texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x-4.0*u_blur_scale.x, input.v_texcoord0.y-4.0*u_blur_scale.y))*0.05;
	color += texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x-3.0*u_blur_scale.x, input.v_texcoord0.y-3.0*u_blur_scale.y))*0.09;
	color += texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x-2.0*u_blur_scale.x, input.v_texcoord0.y-2.0*u_blur_scale.y))*0.12;
	color += texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x-1.0*u_blur_scale.x, input.v_texcoord0.y-1.0*u_blur_scale.y))*0.15;
	color += texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x+0.0*u_blur_scale.x, input.v_texcoord0.y+0.0*u_blur_scale.y))*0.16;
	color += texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x+1.0*u_blur_scale.x, input.v_texcoord0.y+1.0*u_blur_scale.y))*0.15;
	color += texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x+2.0*u_blur_scale.x, input.v_texcoord0.y+2.0*u_blur_scale.y))*0.12;
	color += texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x+3.0*u_blur_scale.x, input.v_texcoord0.y+3.0*u_blur_scale.y))*0.09;
	color += texture2D(s_texColor, s_texColorSampler, vec2(input.v_texcoord0.x+4.0*u_blur_scale.x, input.v_texcoord0.y+4.0*u_blur_scale.y))*0.05;

	return color
		* vec4(u_compose_mult
			 , u_compose_mult
			 , u_compose_mult
			 , u_compose_mult * u_compose_alpha
			 );
}
