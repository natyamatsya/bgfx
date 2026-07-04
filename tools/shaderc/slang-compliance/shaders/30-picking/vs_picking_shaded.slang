// 1-to-1 Slang port of examples/30-picking vs_picking_shaded.sc. Predefined
// u_modelViewProj/u_modelView are auto-declared; u_tint is a custom uniform.
import bgfx_shader;

vec4 u_tint;

struct VSInput
{
	vec3 a_position : POSITION;
	vec3 a_normal   : NORMAL;
};

struct V2F
{
	vec4 pos      : SV_Position;
	vec3 v_pos    : TEXCOORD1;
	vec3 v_view   : TEXCOORD2;
	vec3 v_normal : NORMAL;
	vec4 v_color0 : COLOR0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec3 pos = input.a_position;
	vec3 normal = input.a_normal.xyz*2.0 - 1.0;

	output.pos = mul(u_modelViewProj, vec4(pos, 1.0) );
	output.v_pos = output.pos.xyz;
	output.v_view = mul(u_modelView, vec4(pos, 1.0) ).xyz;

	output.v_normal = mul(u_modelView, vec4(normal, 0.0) ).xyz;

	output.v_color0 = u_tint*vec4(0.8, 0.8, 0.8, 1.0);
	return output;
}
