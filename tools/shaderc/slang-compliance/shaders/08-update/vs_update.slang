// 1-to-1 Slang port of examples/08-update vs_update.sc.
// Predefined u_modelViewProj is auto-declared; passes texcoord through unchanged.
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec3 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
