// 1-to-1 Slang port of examples/43-denoise fs_denoise_spatial_5x5.sc, which sets
// USE_SPATIAL_5X5 == 1 and #includes fs_denoise_spatial_implementation.sh. That include
// holds the entry point body (main + its samplers), not a reusable helper, so it is
// specialized inline here to the 5x5 sample pattern.
// parameters.sh macros expanded inline against u_params:
//   u_texCoordStep = u_params[12].x, u_sigmaDepth = u_params[12].y, u_sigmaNormal = u_params[12].z.
// Highest index used is 12, so u_params reflects at its used extent of 13.
import bgfx_shader;
import bgfx_shader_glsl_compat; // dFdx, dFdy
import normal_encoding;         // NormalDecode

float4 u_params[13];

Texture2D    s_color         : register(t0); // input color, signal to be denoised
SamplerState s_colorSampler  : register(s0);
Texture2D    s_normal        : register(t1); // scene's gbuffer normal, used for edge stopping function
SamplerState s_normalSampler : register(s1);
Texture2D    s_depth         : register(t2); // scene's depth, used for edge stopping function
SamplerState s_depthSampler  : register(s2);

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
	vec3 normal = NormalDecode(texture2D(s_normal, s_normalSampler, texCoord).xyz); // * 2.0 - 1.0;
	float depth = texture2D(s_depth, s_depthSampler, texCoord).x;
	// want depth gradient for edge stopping function
	float depthGradient = abs(dFdx(depth)) + abs(dFdy(depth));

	float du = u_params[12].x * u_viewTexel.x;
	float dv = u_params[12].x * u_viewTexel.y;

	float gaussianWeights[5];
	gaussianWeights[0] = 1.0/16.0;
	gaussianWeights[1] = 4.0/16.0;
	gaussianWeights[2] = 6.0/16.0;
	gaussianWeights[3] = 4.0/16.0;
	gaussianWeights[4] = 1.0/16.0;
	float initialWeight = (gaussianWeights[2]*gaussianWeights[2]);
	int centerIdx = 2;

	vec4 accumulateColor = color * initialWeight;
	float accumulateWeight = initialWeight;

	for (int yy = 0; yy < 5; ++yy)
	{
		for (int xx = 0; xx < 5; ++xx)
		{
			if ((centerIdx == xx) && (centerIdx == yy)) {
				continue;
			}

			float xOffset = float(xx) - float(centerIdx);
			float yOffset = float(yy) - float(centerIdx);
			vec2 sampleTexCoord = texCoord;
			sampleTexCoord.x += xOffset * du;
			sampleTexCoord.y += yOffset * dv;

			vec4 sampleColor = texture2D(s_color, s_colorSampler, sampleTexCoord);
			vec3 sampleNormal = NormalDecode(texture2D(s_normal, s_normalSampler, sampleTexCoord).xyz);
			float normalWeight = pow(saturate(dot(normal, sampleNormal)), u_params[12].z);

			float sampleDepth = texture2D(s_depth, s_depthSampler, sampleTexCoord).x;
			float depthDelta = depth - sampleDepth;
			float depthWeight = exp(-abs(depthDelta) / max(1e-5, u_params[12].y*u_params[12].y));

			float weight = depthWeight * normalWeight;

			// apply gaussian
			weight *= (gaussianWeights[xx]*gaussianWeights[yy]);

			accumulateColor += sampleColor * weight;
			accumulateWeight += weight;
		}
	}

	accumulateColor /= max(accumulateWeight, 1e-5);

	return accumulateColor;
}
