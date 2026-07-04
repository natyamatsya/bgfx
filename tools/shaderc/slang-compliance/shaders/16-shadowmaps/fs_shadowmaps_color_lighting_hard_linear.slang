// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_color_lighting_hard_linear.sc
import bgfx_shader;
import shaderlib;
import bgfx_shader_glsl_compat;
import common;

float4 u_params1;
float4 u_params2;
float4 u_color;
float4 u_materialKa;
float4 u_materialKd;
float4 u_materialKs;
float4 u_lightPosition;
float4 u_lightAmbientPower;
float4 u_lightDiffusePower;
float4 u_lightSpecularPower;
float4 u_lightSpotDirectionInner;
float4 u_lightAttenuationSpotOuter;
float4 u_smSamplingParams;

Texture2D    s_shadowMap0        : register(t4);
SamplerState s_shadowMap0Sampler : register(s4);

struct Shader
{
	vec3 ambi;
	vec3 diff;
	vec3 spec;
};

Shader evalShader(float _diff, float _spec)
{
	Shader shader;

	shader.ambi = u_lightAmbientPower.xyz  * u_lightAmbientPower.w  * u_materialKa.xyz;
	shader.diff = u_lightDiffusePower.xyz  * u_lightDiffusePower.w  * u_materialKd.xyz * _diff;
	shader.spec = u_lightSpecularPower.xyz * u_lightSpecularPower.w * u_materialKs.xyz * _spec;

	return shader;
}

float computeVisibility(Texture2D _sampler
					  , SamplerState _samp
					  , vec4 _shadowCoord
					  , float _bias
					  , vec4 _samplingParams
					  , vec2 _texelSize
					  , float _depthMultiplier
					  , float _minVariance
					  , float _hardness
					  , vec2 _fragCoord
					  )
{
	float visibility;

	vec4 shadowcoord = vec4(_shadowCoord.xy / _shadowCoord.w, _shadowCoord.z, 1.0);

	visibility = hardShadow(_sampler, _samp, shadowcoord, _bias);

	return visibility;
}

struct V2F
{
	vec4 fragCoord    : SV_Position;
	vec3 v_normal     : NORMAL;
	vec3 v_view       : TEXCOORD5;
	vec4 v_shadowcoord : TEXCOORD6;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 colorCoverage;
	float visibility;

	vec2 fragCoord = input.fragCoord.xy;
	vec2 texelSize = vec2_splat(u_params2.z);

	float coverage = texcoordInRange(input.v_shadowcoord.xy/input.v_shadowcoord.w) * 0.3;
	colorCoverage = vec3(coverage, -coverage, -coverage);

	visibility = computeVisibility(s_shadowMap0
					, s_shadowMap0Sampler
					, input.v_shadowcoord
					, u_params1.x
					, u_smSamplingParams
					, texelSize
					, u_params1.w
					, u_params1.z
					, u_params1.z
					, fragCoord
					);

	vec3 v = input.v_view;
	vec3 vd = -normalize(input.v_view);
	vec3 n = input.v_normal;
	Light light = evalLight(v, u_lightPosition, u_lightSpotDirectionInner.xyz, u_lightSpotDirectionInner.w, u_lightAttenuationSpotOuter.w, u_lightAttenuationSpotOuter.xyz);

	vec2 lc = lit(light.ld, n, vd, u_materialKs.w) * light.attn;
	Shader shader = evalShader(lc.x, lc.y);

	//Fog.
	vec3 fogColor = vec3_splat(0.0);
	float fogDensity = 0.0035;
	float LOG2 = 1.442695;
	float z = length(v);
	float fogFactor = clamp(1.0/exp2(fogDensity*fogDensity*z*z*LOG2), 0.0, 1.0);

	vec3 color = u_color.xyz;

	vec3 ambient = shader.ambi * color;
	vec3 brdf    = (shader.diff + shader.spec) * color * visibility;

	vec3 final = toGamma(abs(ambient + brdf)) + (colorCoverage * u_params2.y);
	vec4 fragColor;
	fragColor.xyz = mix(fogColor, final, fogFactor);
	fragColor.w = 1.0;
	return fragColor;
}
