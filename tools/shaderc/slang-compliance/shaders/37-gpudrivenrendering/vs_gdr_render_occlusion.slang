// Slang port of examples/37-gpudrivenrendering vs_gdr_render_occlusion.sc.
// Instanced occlusion-geometry pass: a per-instance model matrix packed into four
// instance-data streams (i_data0..i_data3), transformed by the predefined u_viewProj.
// The stock .sc also lists i_data4 in $input, but it is unused and glslang strips it
// from the vertex-attribute reflection (5 attrs), so it is omitted here to match.
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
	float4 pos : SV_Position;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	float4x4 model = mtxFromCols(input.i_data0, input.i_data1, input.i_data2, input.i_data3);

	float4 worldPos = mul(model, float4(input.a_position, 1.0) );

	V2F output;
	output.pos = mul(u_viewProj, worldPos);
	return output;
}
