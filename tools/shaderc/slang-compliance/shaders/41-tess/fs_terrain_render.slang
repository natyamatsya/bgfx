// Slang port of examples/41-tess fs_terrain_render.sc. Imports the shared terrain_common
// library (slope-map sampler); u_params is declared at this shader's used size ([0] only).
import bgfx_shader;
import terrain_common;

float4 u_params[1];

struct V2F { float2 v_texcoord0 : TEXCOORD0; };

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	float2 s = texture2D(u_SmapSampler, u_SmapSamplerSampler, input.v_texcoord0).rg * u_params[0].x;
	float3 n = normalize(float3(-s, 1.0));
	float  d = clamp(n.z, 0.0, 1.0) / 3.14159;
	return float4(d, d, d, 1.0);
}
