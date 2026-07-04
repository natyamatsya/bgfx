// 1-to-1 Slang port of examples/21-deferred fs_deferred_combine.sc.
import bgfx_shader;

Texture2D    s_albedo        : register(t0);
SamplerState s_albedoSampler : register(s0);
Texture2D    s_light         : register(t1);
SamplerState s_lightSampler  : register(s1);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 albedo = toLinear(texture2D(s_albedo, s_albedoSampler, input.v_texcoord0) );
	vec4 light  = toLinear(texture2D(s_light,  s_lightSampler,  input.v_texcoord0) );
	return toGamma(albedo*light);
}
