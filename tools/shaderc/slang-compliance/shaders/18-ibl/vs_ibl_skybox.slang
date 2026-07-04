// 1-to-1 Slang port of examples/18-ibl vs_ibl_skybox.sc.
// Predefined u_modelViewProj / u_viewRect are auto-declared by shaderc.
// The stock shader also declares "uniform mat4 u_mtx;" but never references it, so
// glslang eliminates it; it is not declared here (declaring it would keep an unused
// UBO member and shift the layout).
// u_params is the custom array from examples/18-ibl/uniforms.sh (u_mtx0..3 = u_params[0..3]).
// Only [0..3] are read, so the active count is 4; the reserved tail (elements [4..11],
// 8*vec4) is reproduced by an unused padding member so the UBO size stays 12*vec4.
import bgfx_shader;

float4 u_params[4];
struct ParamsTailPad { vec4 _unused[8]; };
ParamsTailPad _paramsTailPad;

struct VSInput
{
	vec3 a_position  : POSITION;
	vec2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	vec4 pos   : SV_Position;
	vec3 v_dir : TEXCOORD1;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos = mul(u_modelViewProj, vec4(input.a_position, 1.0) );

	float fov = radians(45.0);
	float height = tan(fov*0.5);
	float aspect = height*(u_viewRect.z / u_viewRect.w);
	vec2 tex = (2.0*input.a_texcoord0-1.0) * vec2(aspect, height);

	mat4 mtx = mtxFromCols(u_params[0], u_params[1], u_params[2], u_params[3]);
	output.v_dir = mul(mtx, vec4(tex, 1.0, 0.0) ).xyz;
	return output;
}
