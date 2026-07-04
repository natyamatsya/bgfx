// 1-to-1 Slang port of examples/43-denoise fs_denoise_apply_lighting.sc.
// parameters.sh is included but no u_params macro is referenced, so u_params is
// dead-stripped and not declared.
import bgfx_shader;

Texture2D    s_color         : register(t0);
SamplerState s_colorSampler  : register(s0);
Texture2D    s_albedo        : register(t1);
SamplerState s_albedoSampler : register(s1);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0;
	vec3 lightColor = texture2D(s_color, s_colorSampler, texCoord).xyz;
	vec3 albedo = texture2D(s_albedo, s_albedoSampler, texCoord).xyz;
	albedo = toLinear(albedo);

	vec3 color = lightColor * albedo;
	color = toGamma(color);

	return vec4(color, 1.0);
}
