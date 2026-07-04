// 1-to-1 Slang port of examples/43-denoise fs_denoise_temporal.sc.
// u_viewRect / u_viewTexel are predefined. GetTexCoordPreviousNoJitter comes from the
// shared shared_functions.sh -> import shared_functions. NormalDecode from normal_encoding.
// parameters.sh is included but no u_params macro is referenced, so u_params is
// dead-stripped and not declared.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
import normal_encoding;         // NormalDecode
import shared_functions;        // GetTexCoordPreviousNoJitter

Texture2D    s_color                : register(t0);
SamplerState s_colorSampler         : register(s0);
Texture2D    s_normal               : register(t1);
SamplerState s_normalSampler        : register(s1);
Texture2D    s_velocity             : register(t2);
SamplerState s_velocitySampler      : register(s2);
Texture2D    s_previousColor        : register(t3); // previous color
SamplerState s_previousColorSampler : register(s3);
Texture2D    s_previousNormal       : register(t4); // previous normal
SamplerState s_previousNormalSampler: register(s4);

#define COS_PI_OVER_4   0.70710678118

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0;

	// read center pixel
	vec4 color = texture2D(s_color, s_colorSampler, texCoord);
	vec3 normal = NormalDecode(texture2D(s_normal, s_normalSampler, texCoord).xyz);

	// offset to last pixel
	vec2 velocity = texture2D(s_velocity, s_velocitySampler, texCoord).xy;
	vec2 texCoordPrev = GetTexCoordPreviousNoJitter(texCoord, velocity);

	// SVGF approach suggests sampling and test/rejecting 4 contributing
	// samples individually and then doing custom bilinear filter of result

	// multiply texCoordPrev by dimensions to get nearest pixels, produces (X.5, Y.5) coordinate
	// under no motion, so subtract half here to get correct weights for bilinear filter.
	// not thrilled by this, feels like something is wrong.
	vec2 screenPixelPrev = texCoordPrev * u_viewRect.zw - vec2_splat(0.5);
	vec2 screenPixelMin = floor(screenPixelPrev);
	vec2 screenPixelMix = fract(screenPixelPrev);

	float x0 = 1.0 - screenPixelMix.x;
	float x1 = screenPixelMix.x;
	float y0 = 1.0 - screenPixelMix.y;
	float y1 = screenPixelMix.y;

	float coordWeights[4];
	coordWeights[0] = x0*y0;
	coordWeights[1] = x1*y0;
	coordWeights[2] = x0*y1;
	coordWeights[3] = x1*y1;

	// adding a half texel here to correct the modification above, in addition to pixel offset
	// to grab adjacent pixels for bilinear filter. not thrilled by this, feels like something is wrong.
	vec2 coords[4];
	coords[0] = (screenPixelMin + vec2(0.5, 0.5)) * u_viewTexel.xy;
	coords[1] = (screenPixelMin + vec2(1.5, 0.5)) * u_viewTexel.xy;
	coords[2] = (screenPixelMin + vec2(0.5, 1.5)) * u_viewTexel.xy;
	coords[3] = (screenPixelMin + vec2(1.5, 1.5)) * u_viewTexel.xy;

	// SVGF paper mentions comparing depths and normals to establish
	// whether samples are similar enough to contribute, but does not
	// describe how. References the following paper, which uses threshold
	// of cos(PI/4) to accept/reject.
	// https://software.intel.com/content/www/us/en/develop/articles/streaming-g-buffer-compression-for-multi-sample-anti-aliasing.html
	// this paper also discusses using depth derivatives to estimate overlapping depth range

	vec4 accumulatedColor = vec4_splat(0.0);
	float accumulatedWeight = 0.0;
	for (int i = 0; i < 4; ++i)
	{
		vec3 sampleNormal = NormalDecode(texture2D(s_previousNormal, s_previousNormalSampler, coords[i]).xyz);
		float normalSimilarity = dot(normal, sampleNormal);
		float weight = (normalSimilarity < COS_PI_OVER_4) ? 0.0 : 1.0;

		vec4 sampleColor = texture2D(s_previousColor, s_previousColorSampler, coords[i]);

		weight *= coordWeights[i];
		accumulatedColor += sampleColor * weight;
		accumulatedWeight += weight;
	}

	if (0.0 < accumulatedWeight)
	{
		accumulatedColor *= (1.0 / accumulatedWeight);
		color = mix(color, accumulatedColor, 0.8);
	}
	else
	{
		// debug colorize
		//color.xyz *= vec3(0.5, 0.01, 0.65);
	}

	return color;
}
