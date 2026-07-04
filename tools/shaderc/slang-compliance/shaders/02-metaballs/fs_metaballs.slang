// Slang port of examples/02-metaballs fs_metaballs.sc (per-stage; no uniforms).

struct V2F
{
	float3 v_normal : TEXCOORD1;
	float4 v_color0 : COLOR0;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	float3 lightDir = float3(0.0, 0.0, -1.0);
	float  ndotl    = dot(normalize(input.v_normal), lightDir);
	float  spec     = pow(ndotl, 30.0);
	return float4(pow(pow(input.v_color0.xyz, float3(2.2, 2.2, 2.2)) * ndotl + spec, float3(1.0/2.2, 1.0/2.2, 1.0/2.2)), 1.0);
}
