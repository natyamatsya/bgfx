// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_color_lighting_pcss_omni.sc
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
float4 u_tetraNormalGreen;
float4 u_tetraNormalYellow;
float4 u_tetraNormalBlue;
float4 u_tetraNormalRed;

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

	vec4 shadowcoord = _shadowCoord;

	visibility = PCSS(_sampler, _samp, shadowcoord, _bias, _samplingParams, _texelSize, _fragCoord);

	return visibility;
}

struct V2F
{
	vec4 fragCoord  : SV_Position;
	vec4 v_position : TEXCOORD7;
	vec3 v_normal   : NORMAL;
	vec3 v_view     : TEXCOORD5;
	vec4 v_texcoord1 : TEXCOORD1;
	vec4 v_texcoord2 : TEXCOORD2;
	vec4 v_texcoord3 : TEXCOORD3;
	vec4 v_texcoord4 : TEXCOORD4;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 colorCoverage;
	float visibility;

	vec2 fragCoord = input.fragCoord.xy;
	vec2 texelSize = vec2_splat(u_params2.z/4.0);

	vec4 faceSelection;
	vec3 pos = input.v_position.xyz;
	faceSelection.x = dot(u_tetraNormalGreen.xyz,  pos);
	faceSelection.y = dot(u_tetraNormalYellow.xyz, pos);
	faceSelection.z = dot(u_tetraNormalBlue.xyz,   pos);
	faceSelection.w = dot(u_tetraNormalRed.xyz,    pos);

	vec4 shadowcoord;
	float faceMax = max(max(faceSelection.x, faceSelection.y), max(faceSelection.z, faceSelection.w));
	if (faceSelection.x == faceMax)
	{
		shadowcoord = input.v_texcoord1;

		float coverage = texcoordInRange(shadowcoord.xy/shadowcoord.w) * 0.3;
		colorCoverage = vec3(-coverage, coverage, -coverage);
	}
	else if (faceSelection.y == faceMax)
	{
		shadowcoord = input.v_texcoord2;

		float coverage = texcoordInRange(shadowcoord.xy/shadowcoord.w) * 0.3;
		colorCoverage = vec3(coverage, coverage, -coverage);
	}
	else if (faceSelection.z == faceMax)
	{
		shadowcoord = input.v_texcoord3;

		float coverage = texcoordInRange(shadowcoord.xy/shadowcoord.w) * 0.3;
		colorCoverage = vec3(-coverage, -coverage, coverage);
	}
	else // (faceSelection.w == faceMax)
	{
		shadowcoord = input.v_texcoord4;

		float coverage = texcoordInRange(shadowcoord.xy/shadowcoord.w) * 0.3;
		colorCoverage = vec3(coverage, -coverage, -coverage);
	}

	visibility = computeVisibility(s_shadowMap0
					, s_shadowMap0Sampler
					, shadowcoord
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
