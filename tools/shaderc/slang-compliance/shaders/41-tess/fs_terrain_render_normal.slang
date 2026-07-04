// Slang port of examples/41-tess fs_terrain_render_normal.sc. As fs_terrain_render, but
// outputs the encoded normal. Shared terrain_common; u_params sized to its used extent.
import bgfx_shader;
import terrain_common;

float4 u_params[1];

struct V2F { float2 v_texcoord0 : TEXCOORD0; };

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	float2 s = texture2D(u_SmapSampler, u_SmapSamplerSampler, input.v_texcoord0).rg * u_params[0].x;
	float3 n = normalize(float3(-s, 1.0));
	return float4(abs(n), 1.0);
}
