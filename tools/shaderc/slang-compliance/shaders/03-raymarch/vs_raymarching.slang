// 1-to-1 Slang port of examples/03-raymarch vs_raymarching.sc.
// Predefined u_modelViewProj is auto-declared.
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec4 a_color0    : COLOR0;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );
	output.v_color0 = input.a_color0;
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
