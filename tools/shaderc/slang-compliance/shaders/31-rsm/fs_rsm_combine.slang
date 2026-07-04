// 1-to-1 Slang port of examples/31-rsm fs_rsm_combine.sc.
// Final combine: directional light + hardware PCF shadow, mixed with the accumulated
// RSM light buffer (u_rsmAmount). The hardShadow/PCF helpers are defined inline in the
// stock .sc body (not a shared #include), so they stay inline here.
// SAMPLER2DSHADOW(s_shadowMap, 4) -> a comparison sampler; shadow2D -> SampleCmp.
import bgfx_shader;
import shaderlib;               // toClipSpaceDepth, clipToWorld
import bgfx_shader_glsl_compat; // mix, greaterThan, lessThan

Texture2D    s_normal        : register(t0);
SamplerState s_normalSampler : register(s0);
Texture2D    s_color         : register(t1);
SamplerState s_colorSampler  : register(s1);
Texture2D    s_light         : register(t2);
SamplerState s_lightSampler  : register(s2);
Texture2D    s_depth         : register(t3);
SamplerState s_depthSampler  : register(s3);

// SAMPLER2DSHADOW(s_shadowMap, 4): a comparison sampler.
Texture2D              s_shadowMap        : register(t4);
SamplerComparisonState s_shadowMapSampler : register(s4);

// Single directional light for entire scene
uniform vec4 u_lightDir;
uniform mat4 u_invMvp;
uniform mat4 u_lightMtx;
uniform vec4 u_shadowDimsInv;
uniform vec4 u_rsmAmount;

float hardShadow(Texture2D _sampler, SamplerComparisonState _cmp, vec4 _shadowCoord, float _bias)
{
	vec2 texCoord = _shadowCoord.xy;
	return _sampler.SampleCmp(_cmp, texCoord.xy, _shadowCoord.z-_bias);
}

float PCF(Texture2D _sampler, SamplerComparisonState _cmp, vec4 _shadowCoord, float _bias, vec2 _texelSize)
{
	vec2 texCoord = _shadowCoord.xy;

	bool outside = any(greaterThan(texCoord, vec2_splat(1.0)))
		|| any(lessThan   (texCoord, vec2_splat(0.0)))
		;

	if (outside)
	{
		return 1.0;
	}

	float result = 0.0;
	vec2 offset = _texelSize * _shadowCoord.w;

	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(-1.5, -1.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(-1.5, -0.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(-1.5,  0.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(-1.5,  1.5) * offset, 0.0, 0.0), _bias);

	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(-0.5, -1.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(-0.5, -0.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(-0.5,  0.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(-0.5,  1.5) * offset, 0.0, 0.0), _bias);

	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(0.5, -1.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(0.5, -0.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(0.5,  0.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(0.5,  1.5) * offset, 0.0, 0.0), _bias);

	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(1.5, -1.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(1.5, -0.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(1.5,  0.5) * offset, 0.0, 0.0), _bias);
	result += hardShadow(_sampler, _cmp, _shadowCoord + vec4(vec2(1.5,  1.5) * offset, 0.0, 0.0), _bias);

	return result / 16.0;
}

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 n  = texture2D(s_normal, s_normalSampler, input.v_texcoord0).xyz;
	// Expand out normal
	n = n*2.0+-1.0;
	vec3 l = u_lightDir.xyz;//normalize(vec3(-0.8,0.75,-1.0));
	float dirLightIntensity = 1.0;
	float dirLight = max(0.0,dot(n,l)) * dirLightIntensity;

	// Apply shadow map

	// Get world position so we can transform it into light space, to look into shadow map
	vec2 texCoord = input.v_texcoord0.xy;
	float deviceDepth = texture2D(s_depth, s_depthSampler, texCoord).x;
	float depth       = toClipSpaceDepth(deviceDepth);
	vec3 clip = vec3(texCoord * 2.0 - 1.0, depth);
	clip.y = -clip.y; // !BGFX_SHADER_LANGUAGE_GLSL
	vec3 wpos = clipToWorld(u_invMvp, clip);

	const float shadowMapOffset = 0.003;
	vec3 posOffset = wpos + n.xyz * shadowMapOffset;
	vec4 shadowCoord = mul(u_lightMtx, vec4(posOffset, 1.0) );

	shadowCoord.y *= -1.0; // !BGFX_SHADER_LANGUAGE_GLSL

	float shadowMapBias = 0.001;
	vec2 texelSize = vec2_splat(u_shadowDimsInv.x);

	shadowCoord.xy /= shadowCoord.w;
	shadowCoord.xy = shadowCoord.xy*0.5 + 0.5;

	// BGFX_SHADER_LANGUAGE_GLSL-only z remap is omitted for the non-GLSL target.

	float visibility = PCF(s_shadowMap, s_shadowMapSampler, shadowCoord, shadowMapBias, texelSize);

	dirLight *= visibility;

	// Light from light buffer
	vec3 albedo = texture2D(s_color, s_colorSampler, input.v_texcoord0).xyz;
	vec3 lightBuffer = texture2D(s_light, s_lightSampler, input.v_texcoord0).xyz;

	vec4 fragColor;
	fragColor.xyz = mix(dirLight * albedo, lightBuffer * albedo, u_rsmAmount.x);
	fragColor.w = 1.0;
	return fragColor;
}
