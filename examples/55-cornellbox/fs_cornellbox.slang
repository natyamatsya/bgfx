// Fullscreen-quad fragment shader (Slang): samples the compute-written Cornell Box image.
import bgfx_shader;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

struct V2F
{
	float4 pos         : SV_Position;
	float2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	return s_texColor.Sample(s_texColorSampler, input.v_texcoord0);
}
