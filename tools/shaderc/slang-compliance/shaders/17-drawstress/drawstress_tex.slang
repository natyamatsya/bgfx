// 1-to-1 Slang port of examples/17-drawstress vs_drawstress_tex.sc / fs_drawstress_tex.sc.
// u_modelViewProj is a predefined uniform provided by the bgfx runtime.
import bgfx_shader;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

float4x4 u_modelViewProj;

struct VSInput
{
	float3 a_position  : POSITION;
	float4 a_color0    : COLOR0;
	float2 a_texcoord0 : TEXCOORD0;
};

struct V2F
{
	float4 pos        : SV_Position;
	float4 v_color0   : COLOR0;
	float2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;
	output.pos        = mul(u_modelViewProj, float4(input.a_position, 1.0));
	output.v_color0   = input.a_color0;
	output.v_texcoord0 = input.a_texcoord0;
	return output;
}

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	return texture2D(s_texColor, s_texColorSampler, input.v_texcoord0) * input.v_color0;
}
