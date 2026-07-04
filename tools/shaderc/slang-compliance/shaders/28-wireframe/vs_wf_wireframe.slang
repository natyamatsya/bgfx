// 1-to-1 Slang port of examples/28-wireframe vs_wf_wireframe.sc.
// Predefined u_modelViewProj / u_model are auto-declared; u_model[0] -> u_model.
// u_params is the custom array from uniforms.sh (declared vec4[3]). This VS reads only
// u_camPos = u_params[0].xyz, so the active extent is 1; the reserved tail (elements
// [1..2], 2*vec4) is reproduced by an unused padding member so the UBO size stays 3*vec4.
import bgfx_shader;

float4 u_params[1];              // u_camPos = u_params[0].xyz
struct ParamsTailPad { vec4 _unused[2]; };
ParamsTailPad _paramsTailPad;

struct VSInput
{
	vec3 a_position : POSITION;
	vec3 a_color1   : COLOR1;
};

struct V2F
{
	vec4 pos    : SV_Position;
	vec3 v_view : TEXCOORD0;
	vec3 v_bc   : TEXCOORD1;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );

	output.v_view = u_params[0].xyz - mul(u_model, vec4(input.a_position, 1.0) ).xyz;
	output.v_bc = input.a_color1;
	return output;
}
