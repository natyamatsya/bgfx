// Slang port of examples/54-s2h/fs_s2h_quadpost_scene.sc.
//
// The stock shader includes s2h/s2h_bgfx.sh for the library's compatibility macros but
// calls nothing from S2H; under Slang those spellings come from bgfx_shader_glsl_compat.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix

vec4 u_s2hTime;

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
	float grid = step(0.96f, frac(uv.x * 10.0f) ) + step(0.96f, frac(uv.y * 10.0f) );
	float wave = 0.5f + 0.5f * sin(u_s2hTime.x + uv.x * 8.0f + uv.y * 5.0f);
	vec3 color = mix(vec3(0.06f, 0.1f, 0.25f), vec3(0.9f, 0.25f, 0.1f), wave);
	return vec4(mix(color, vec3(1.0f, 1.0f, 1.0f), grid), 1.0f);
}
