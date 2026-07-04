// 1-to-1 Slang port of examples/44-sss fs_sss_deferred_combine.sc.
// Deferred lighting combine. u_params referenced up to index 7 (u_worldToView3),
// so the array reflects at its used extent (8).
// NDCToViewspace is inline in the stock .sc body -> stays inline.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
import normal_encoding;         // NormalDecode

Texture2D    s_color         : register(t0);
SamplerState s_colorSampler  : register(s0);
Texture2D    s_normal        : register(t1);
SamplerState s_normalSampler : register(s1);
Texture2D    s_depth         : register(t2);
SamplerState s_depthSampler  : register(s2);
Texture2D    s_shadows        : register(t3);
SamplerState s_shadowsSampler : register(s3);

// parameters.sh macros expanded inline against u_params:
//   u_ndcToViewMul=[2].xy u_ndcToViewAdd=[2].zw u_lightPosition=[3].xyz
//   u_displayShadows=[3].w u_worldToView0..3=[4..7]
float4 u_params[8];

// from assao sample, cs_assao_prepare_depths.sc
vec3 NDCToViewspace( vec2 pos, float viewspaceDepth )
{
	vec3 ret;

	ret.xy = (u_params[2].xy * pos.xy + u_params[2].zw) * viewspaceDepth;

	ret.z = viewspaceDepth;

	return ret;
}

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0;

	vec4 colorId = texture2D(s_color, s_colorSampler, texCoord);
	vec3 color = toLinear(colorId.xyz);
	float materialId = colorId.w;

	if (0.0 < materialId)
	{
		vec4 normalRoughness = texture2D(s_normal, s_normalSampler, texCoord);
		vec3 normal = NormalDecode(normalRoughness.xyz);
		float roughness = normalRoughness.w;

		// transform normal into view space
		mat4 worldToView = mtxFromCols(
			  u_params[4]
			, u_params[5]
			, u_params[6]
			, u_params[7]
			);
		vec3 vsNormal = mul(worldToView, vec4(normal, 0.0)).xyz;

		// read depth and recreate position
		float linearDepth = texture2D(s_depth, s_depthSampler, texCoord).x;
		vec3 viewSpacePosition = NDCToViewspace(texCoord, linearDepth);

		float shadow = texture2D(s_shadows, s_shadowsSampler, texCoord).x;

		// need to get a valid view vector for any microfacet stuff :(
		float gloss = 1.0-roughness;
		float specPower = 62.0 * gloss + 2.0;

		vec3 light = (u_params[3].xyz - viewSpacePosition);
		float lightDistSq = dot(light, light) + 1e-5;
		light = normalize(light);
		float NdotL = saturate(dot(vsNormal, light));
		float diffuse = NdotL * (1.0/lightDistSq);
		float specular = 5.0 * pow(NdotL, specPower);

		float lightAmount = mix(diffuse, specular, 0.04) * shadow;

		color = (color * lightAmount);
		color = toGamma(color);

		// debug display shadows only
		if (0.0 < u_params[3].w)
		{
			color = vec3_splat(shadow);
		}
	}
	// else, assume color is unlit

	return vec4(color, 1.0);
}
