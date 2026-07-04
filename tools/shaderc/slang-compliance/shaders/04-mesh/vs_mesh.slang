// 1-to-1 Slang port of examples/04-mesh vs_mesh.sc. The bgfx predefined uniforms
// (u_modelViewProj, u_modelView) are auto-declared by shaderc -- only the custom
// u_time is declared here. Per-stage: keeps the VS/FS uniform envelopes independent.
import bgfx_shader;

vec4 u_time;

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
	vec3 pos = input.a_position;

	float sx = sin(pos.x*32.0+u_time.x*4.0)*0.5+0.5;
	float cy = cos(pos.y*32.0+u_time.x*4.0)*0.5+0.5;
	vec3 displacement = vec3(sx, cy, sx*cy);
	vec3 normal = input.a_normal.xyz*2.0 - 1.0;

	pos = pos + normal*displacement*vec3(0.06, 0.06, 0.06);

	V2F output;
	output.pos = mul(u_modelViewProj, vec4(pos, 1.0) );
	output.v_pos = output.pos.xyz;
	output.v_view = mul(u_modelView, vec4(pos, 1.0) ).xyz;

	output.v_normal = mul(u_modelView, vec4(normal, 0.0) ).xyz;

	float len = length(displacement)*0.4+0.6;
	output.v_color0 = vec4(len, len, len, 1.0);
	return output;
}
