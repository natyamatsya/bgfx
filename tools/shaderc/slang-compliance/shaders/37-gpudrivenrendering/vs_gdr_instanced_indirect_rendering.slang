// Slang port of examples/37-gpudrivenrendering vs_gdr_instanced_indirect_rendering.sc.
// Instanced indirect draw: the per-instance model matrix comes from i_data0..i_data3
// (i_data0.xyz is the first column, i_data0.w carries the material id passed to the FS).
import bgfx_shader;

struct VSInput
{
	float3 a_position : POSITION;
	float4 i_data0    : TEXCOORD7;
	float4 i_data1    : TEXCOORD6;
	float4 i_data2    : TEXCOORD5;
	float4 i_data3    : TEXCOORD4;
};

struct V2F
{
	float4 pos                          : SV_Position;
	nointerpolation float v_materialID  : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	float4x4 model = mtxFromCols(
		  float4(input.i_data0.xyz, 0.0)
		, input.i_data1
		, input.i_data2
		, input.i_data3
		);

	V2F output;
	output.v_materialID = input.i_data0.w;

	float4 worldPos = mul(model, float4(input.a_position, 1.0) );
	output.pos = mul(u_viewProj, worldPos);
	return output;
}
