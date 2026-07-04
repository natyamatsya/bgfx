// Slang port of examples/02-metaballs vs_metaballs.sc. Predefined u_modelViewProj and
// u_model are auto-declared by shaderc (u_model as a single float4x4 -- the stock
// u_model[0] strips to one matrix). Per-stage: the FS uses no uniforms.

struct VSInput
{
	float3 a_position : POSITION;
	float3 a_normal   : NORMAL;
	float4 a_color0   : COLOR0;
};

struct V2F
{
	float4 pos      : SV_Position;
	float3 v_normal : TEXCOORD1;
	float4 v_color0 : COLOR0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos      = mul(u_modelViewProj, float4(input.a_position, 1.0));
	output.v_normal = mul(u_model, float4(input.a_normal, 0.0)).xyz;
	output.v_color0 = input.a_color0;
	return output;
}
