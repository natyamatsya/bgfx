// 1-to-1 Slang port of examples/19-oit vs_oit.sc.
// u_model / u_viewProj / u_view are auto-provided predefined uniforms.
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
};

struct V2F
{
	vec4 pos   : SV_Position;
	vec4 v_pos : TEXCOORD4;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	vec3 wpos = mul(u_model, vec4(input.a_position, 1.0) ).xyz;
	output.pos = mul(u_viewProj, vec4(wpos, 1.0) );
	output.v_pos = output.pos;
	vec4 temp = mul(u_view, vec4(wpos, 1.0) );
	output.v_pos.x = temp.z;
	return output;
}
