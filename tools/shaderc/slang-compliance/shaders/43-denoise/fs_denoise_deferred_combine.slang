// 1-to-1 Slang port of examples/43-denoise fs_denoise_deferred_combine.sc.
// ShadertoyNoise / ModHelper are inline in the stock .sc body -> stay inline.
// gl_FragCoord -> SV_Position input field.
// parameters.sh macros expanded inline against u_params:
//   u_frameIdx = u_params[11].x, u_noiseType = u_params[11].y.
// Highest index used is 11, so u_params reflects at its used extent of 12.
import bgfx_shader;
import normal_encoding; // NormalDecode

float4 u_params[12];

Texture2D    s_color         : register(t0);
SamplerState s_colorSampler  : register(s0);
Texture2D    s_normal        : register(t1);
SamplerState s_normalSampler : register(s1);

float ShadertoyNoise (vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

int ModHelper (float a, float b)
{
	return int( a - (b*floor(a/b)));
}

struct V2F
{
	vec4 gl_FragCoord : SV_Position;
	vec2 v_texcoord0  : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0;

	// mess with result so there's something to denosie
	float sn = 1.0;
	if (1.5 < u_params[11].y)
	{
		sn = ShadertoyNoise(input.gl_FragCoord.xy + vec2(314.0, 159.0)*u_params[11].x);
		sn = (sn < 0.5) ? 0.0 : 1.0;
	}
	else if (0.5 < u_params[11].y)
	{
		// having trouble compiling for gles when using % or mod :(
		int modCoordX = ModHelper(input.gl_FragCoord.x, 2.0);
		int modCoordY = ModHelper(input.gl_FragCoord.y, 2.0);
		int frameSelect = modCoordY * 2 + modCoordX;
		int frameMod4 = ModHelper(u_params[11].x, 4.0);
		sn = (frameSelect == frameMod4) ? 1.0 : 0.0;
	}

	vec4 normalRoughness = texture2D(s_normal, s_normalSampler, texCoord).xyzw;
	vec3 normal = NormalDecode(normalRoughness.xyz);
	float roughness = 0.5;

	// need to get a valid view vector for any microfacet stuff :(
	float gloss = 1.0-roughness;
	float specPower = 1022.0 * gloss + 2.0;

	vec3 light = normalize(vec3(-0.2, 1.0, -0.2));
	float NdotL = saturate(dot(normal, light));
	float diff = NdotL*0.99 + 0.01;
	float spec = 5.0 * pow(NdotL, specPower);

	float lightAmt = (diff + spec) * sn;

	return vec4(vec3_splat(lightAmt), 1.0);
}
