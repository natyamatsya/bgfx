// 1-to-1 Slang port of examples/23-vectordisplay vs_vectordisplay_fb.sc.
// Predefined u_modelViewProj is auto-declared.
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec2 a_texcoord0 : TEXCOORD0;
	vec4 a_color0    : COLOR0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_color0    : COLOR0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	output.v_color0    = input.a_color0;
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
