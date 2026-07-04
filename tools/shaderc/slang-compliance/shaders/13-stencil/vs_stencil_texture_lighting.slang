// 1-to-1 Slang port of examples/13-stencil vs_stencil_texture_lighting.sc.
// Predefined u_modelViewProj / u_modelView are auto-declared; use them directly.
import bgfx_shader;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec4 a_normal    : NORMAL;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_normal    : NORMAL;
	vec3 v_view      : TEXCOORD1;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );

	vec4 normal = input.a_normal * 2.0 - 1.0;
	output.v_normal = mul(u_modelView, vec4(normal.xyz, 0.0) ).xyz;
	output.v_view   = mul(u_modelView, vec4(input.a_position, 1.0) ).xyz;

	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
