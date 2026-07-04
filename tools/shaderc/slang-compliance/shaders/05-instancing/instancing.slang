// 1-to-1 Slang port of examples/05-instancing vs_instancing.sc / fs_instancing.sc.
// Predefined u_viewProj is auto-declared -- never declare it here. i_data0..4 are
// per-instance vertex attributes carried on the TEXCOORD7..3 semantics (bgfx feeds
// them from a separate instance buffer). mtxFromCols matches GLSL's column-setting
// mat4(cols) (Slang's matrix constructor is row-major).
import bgfx_shader;

struct VSInput
{
	vec3 a_position : POSITION;
	vec4 a_color0   : COLOR0;
	vec4 i_data0    : TEXCOORD7;
	vec4 i_data1    : TEXCOORD6;
	vec4 i_data2    : TEXCOORD5;
	vec4 i_data3    : TEXCOORD4;
	vec4 i_data4    : TEXCOORD3;
};

struct V2F
{
	vec4 pos      : SV_Position;
	vec4 v_color0 : COLOR0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	mat4 model = mtxFromCols(input.i_data0, input.i_data1, input.i_data2, input.i_data3);

	vec4 worldPos = mul(model, vec4(input.a_position, 1.0) );

	V2F output;
	output.pos      = mul(u_viewProj, worldPos);
	output.v_color0 = input.a_color0 * input.i_data4;
	return output;
}

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	return input.v_color0;
}
