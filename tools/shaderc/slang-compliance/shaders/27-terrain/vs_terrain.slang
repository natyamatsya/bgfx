// 1-to-1 Slang port of examples/27-terrain vs_terrain.sc.
// Predefined u_modelViewProj is auto-declared; use directly.
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
	vec3 v_position  : TEXCOORD1;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.v_position = input.a_position.xyz;
	output.v_texcoord0 = input.a_texcoord0;

	output.pos = mul(u_modelViewProj, vec4(output.v_position.xyz, 1.0));
	return output;
}
