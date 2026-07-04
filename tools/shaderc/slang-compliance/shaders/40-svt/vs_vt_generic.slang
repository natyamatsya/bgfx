// 1-to-1 Slang port of examples/40-svt vs_vt_generic.sc. Predefined u_model/u_viewProj are
// auto-declared; u_model[0] -> u_model (single matrix).
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec3 wpos = mul(u_model, vec4(input.a_position, 1.0) ).xyz;
	output.pos = mul(u_viewProj, vec4(wpos, 1.0) );
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
