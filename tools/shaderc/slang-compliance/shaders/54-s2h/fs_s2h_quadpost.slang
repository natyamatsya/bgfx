// Slang port of examples/54-s2h/fs_s2h_quadpost.sc.
//
// The stock shader includes s2h/s2h_bgfx.sh for the library's compatibility macros but
// calls nothing from S2H; under Slang those spellings come from bgfx_shader_glsl_compat.
// u_viewRect is a bgfx predefined uniform, so it is used without being declared.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix

Texture2D    s_quadPostColor        : register(t0);
SamplerState s_quadPostColorSampler : register(s0);

vec4 u_s2hMouse;

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 uv = input.v_texcoord0;
	vec3 color = texture2D(s_quadPostColor, s_quadPostColorSampler, uv).rgb;
	vec2 mouseUv = u_s2hMouse.xy / u_viewRect.zw;
	vec2 delta = uv - mouseUv;
	float highlight = 1.0f - smoothstep(0.02f, 0.025f, length(delta) );
	color = mix(color, vec3(1.0f, 1.0f, 0.0f), highlight);
	return vec4(color, 1.0f);
}
