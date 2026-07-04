// 1-to-1 Slang port of examples/21-deferred fs_deferred_combine_ta.sc.
// SAMPLER2DARRAY(s_albedo, 0) -> Texture2DArray + SamplerState; texture2DArray -> .Sample.
import bgfx_shader;

Texture2DArray s_albedo        : register(t0);
SamplerState   s_albedoSampler : register(s0);
Texture2D      s_light         : register(t1);
SamplerState   s_lightSampler  : register(s1);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 albedo = toLinear(s_albedo.Sample(s_albedoSampler, vec3(input.v_texcoord0, 0.0) ) );
	vec4 light  = toLinear(texture2D(s_light, s_lightSampler, input.v_texcoord0) );
	return toGamma(albedo*light);
}
