// Slang port of examples/42-bunnylod vs_bunnylod.sc / fs_bunnylod.sc.
// u_modelViewProj and u_model (single matrix) are auto-declared by shaderc.

struct VSInput
{
	float3 a_position : POSITION;
	float3 a_normal   : NORMAL;
};

struct V2F
{
	float4 pos     : SV_Position;
	float3 v_world : TEXCOORD0;
	float4 v_color0 : COLOR0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos     = mul(u_modelViewProj, float4(input.a_position, 1.0));
	output.v_world = mul(u_model, float4(input.a_position, 1.0)).xyz;
	output.v_color0 = float4(input.a_normal, 1.0);
	return output;
}

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	float3 normal   = normalize(cross(ddx(input.v_world), ddy(input.v_world)));
	float3 lightDir = float3(0.0, 0.0, 1.0);
	float  ndotl    = max(dot(normal, lightDir), 0.0);
	float  spec     = pow(ndotl, 30.0);
	return input.v_color0 * ndotl + spec;
}
