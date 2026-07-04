// Slang port of examples/31-rsm vs_rsm_combine.sc (per-stage: VS only, so its
// uniform set stays independent of the fragment shader's).
import bgfx_shader;

float4x4 u_modelViewProj;

struct VSInput
{
	float3 a_position  : POSITION;
	float2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	float4 pos         : SV_Position;
	float2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos         = mul(u_modelViewProj, float4(input.a_position, 1.0) );
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}
