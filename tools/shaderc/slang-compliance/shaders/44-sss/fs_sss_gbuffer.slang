// 1-to-1 Slang port of examples/44-sss fs_sss_gbuffer.sc.
// MRT G-buffer: gl_FragData[0]/[1] -> a struct of SV_Target0/SV_Target1.
// cotangentFrame is defined inline in the stock .sc body, so it stays inline here.
// parameters.sh is included but no u_params macro is referenced, so u_params is
// dead-stripped and not declared.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix, dFdx, dFdy
import normal_encoding;         // NormalEncode

Texture2D    s_albedo        : register(t0);
SamplerState s_albedoSampler : register(s0);
Texture2D    s_normal        : register(t1);
SamplerState s_normalSampler : register(s1);

// http://www.thetenthplanet.de/archives/1180
// "followup: normal mapping without precomputed tangents"
mat3 cotangentFrame(vec3 N, vec3 p, vec2 uv)
{
	// get edge vectors of the pixel triangle
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	// solve the linear system
	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame
	float invMax = rsqrt(max(dot(T,T), dot(B,B)));
	return mtxFromCols(T*invMax, B*invMax, N);
}

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
};

struct GBuffer
{
	vec4 gbuffer0 : SV_Target0;
	vec4 gbuffer1 : SV_Target1;
};

[shader("fragment")]
GBuffer fragmentMain(V2F input)
{
	vec3 albedo = toLinear(texture2D(s_albedo, s_albedoSampler, input.v_texcoord0).xyz);

	// get vertex normal
	vec3 normal = normalize(input.v_normal);

	// get normal map normal, unpack, and calculate z
	vec3 normalMap;
	normalMap.xy = texture2D(s_normal, s_normalSampler, input.v_texcoord0).xy;
	normalMap.xy = normalMap.xy * 2.0 - 1.0;
	normalMap.z = sqrt(1.0 - dot(normalMap.xy, normalMap.xy));

	// swap x and y, because the brick texture looks flipped, don't copy this...
	normalMap.xy = normalMap.yx;

	// perturb geometry normal by normal map
	vec3 pos = input.v_texcoord1.xyz; // contains world space pos
	mat3 TBN = cotangentFrame(normal, pos, input.v_texcoord0);
	vec3 bumpedNormal = normalize(mul(TBN, normalMap));

	// need some proxy for roughness value w/o roughness texture
	// assume horizontal (blue) normal map is smooth, and then
	// modulate with albedo for some higher frequency detail
	float roughness = normalMap.z * mix(0.9, 1.0, albedo.y);
	roughness = roughness * 0.6 + 0.2;

	vec3 bufferNormal = NormalEncode(bumpedNormal);

	GBuffer output;
	output.gbuffer0 = vec4(toGamma(albedo), 1.0);
	output.gbuffer1 = vec4(bufferNormal, roughness);
	return output;
}
