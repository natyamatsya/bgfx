// Slang port of examples/08-update fs_update_mip.sc (explicit LOD: texture2DLod).
import bgfx_shader;

uniform float4 u_texMipLevel;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

struct V2F
{
	float4 pos         : SV_Position;
	float3 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	return texture2DLod(s_texColor, s_texColorSampler, input.v_texcoord0.xy * 0.5 + 0.5, u_texMipLevel.x);
}
