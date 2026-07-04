// Slang port of examples/01-cubes vs_cubes.sc / fs_cubes.sc.
// Loose global uniform -> implicit $Globals constant buffer (matches bgfx's model).
// u_modelViewProj is recognized as a predefined uniform by the bgfx runtime.

float4x4 u_modelViewProj;

struct VSInput
{
	float3 a_position : POSITION;
	float4 a_color0   : COLOR0;
};

struct V2F
{
	float4 pos      : SV_Position;
	float4 v_color0 : COLOR0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos      = mul(u_modelViewProj, float4(input.a_position, 1.0));
	output.v_color0 = input.a_color0;
	return output;
}

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	return input.v_color0;
}
