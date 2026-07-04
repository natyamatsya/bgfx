// 1-to-1 Slang port of examples/38-bloom fs_bloom_combine.sc.
// Adds the bloom (light) chain to the albedo, clamps, and gamma-corrects.
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
	vec3 hdrColor = texture2D(s_albedo, s_albedoSampler, input.v_texcoord0).rgb;

	hdrColor += texture2D(s_light, s_lightSampler, input.v_texcoord0).rgb;

	// instead of some fancy tonemapping operator, we just clamp it, to keep it simple.
	vec3 finalColor = clamp(hdrColor, 0.0, 1.0);

	float g = 2.2;
	return vec4(pow(finalColor, vec3(1.0 / g, 1.0 / g, 1.0 / g) ), 1.0);
}
