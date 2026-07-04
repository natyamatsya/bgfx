// 1-to-1 Slang port of examples/18-ibl vs_ibl_mesh.sc.
// Predefined u_modelViewProj / u_model (single matrix) are auto-declared by shaderc.
// u_params is the custom uniform array from examples/18-ibl/uniforms.sh:
//   u_camPos = u_params[7].xyz.
// The stock array is declared u_params[12] but this stage only reads [7], so glslang
// reflects the active count 8 while still reserving the full [12] in $Globals. Slang
// reflects the declared extent, so u_params is declared [8] to match the active count
// and the reserved tail (elements [8..11], 4*vec4) is reproduced by an unused padding
// member so the UBO size stays at 12*vec4.
import bgfx_shader;

float4 u_params[8];
struct ParamsTailPad { vec4 _unused[4]; };
ParamsTailPad _paramsTailPad;

struct VSInput
{
	vec3 a_position : POSITION;
	vec3 a_normal   : NORMAL;
};

struct V2F
{
	vec4 pos      : SV_Position;
	vec3 v_normal : NORMAL;
	vec3 v_view   : TEXCOORD2;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );

	output.v_view = u_params[7].xyz - mul(u_model, vec4(input.a_position, 1.0) ).xyz; // u_camPos

	vec3 normal = input.a_normal * 2.0 - 1.0;
	output.v_normal = mul(u_model, vec4(normal, 0.0) ).xyz;
	return output;
}
