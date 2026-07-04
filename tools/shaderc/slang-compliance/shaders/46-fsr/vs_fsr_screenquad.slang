// 1-to-1 Slang port of examples/46-fsr vs_fsr_screenquad.sc.
// Predefined u_modelViewProj is auto-declared.
import bgfx_shader;

struct VSInput
{
	vec4 a_position  : POSITION;
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
	output.pos = mul(u_modelViewProj, vec4(input.a_position.xyz, 1.0));
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
