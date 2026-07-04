// 1-to-1 Slang port of examples/09-hdr vs_hdr_mesh.sc.
// u_modelViewProj / u_modelView are auto-provided predefined uniforms.
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
	vec3 a_normal   : NORMAL;
};

struct V2F
{
	vec4 pos      : SV_Position;
	vec3 v_pos    : TEXCOORD5;
	vec3 v_view   : TEXCOORD6;
	vec3 v_normal : NORMAL;
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
	return output;
}
