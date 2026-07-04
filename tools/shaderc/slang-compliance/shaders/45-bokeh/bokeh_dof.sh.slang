// Slang port of examples/45-bokeh bokeh_dof.sh -- the bokeh depth-of-field helpers shared
// by the dof shaders (downsample, debug, single/second pass). `import bokeh_dof;`.
//
// Modularity notes:
//   * These are the shared #include'd helpers, so they live here once as `public` functions.
//   * The stock helpers reference u_params[...] accessors (u_maxBlurSize, u_radiusScale,
//     u_frameIdx, u_lobeRotation, u_lobeCount, u_lobeRadiusMin, u_lobeRadiusDelta2x) and the
//     predefined u_viewRect/u_viewTexel through the parameters.sh macros. u_params is a
//     partially-used vec4[] whose active extent differs per shader and predefined uniforms
//     are injected only into entry-point source, so -- as in 41-tess terrain_common -- none
//     of those live here; each helper takes the needed components as parameters and the
//     entry shader extracts them from its own u_params / u_viewRect / u_viewTexel.
//   * USE_PACKED_COLOR_AND_BLUR is a compile-time switch in the stock header (set only in
//     fs_bokeh_dof_second_pass); it is passed as a literal `usePacked` bool so Slang folds it.
import bgfx_shader;             // vec types, texture2DLod
import bgfx_shader_glsl_compat; // mix

#define TWO_PI			(6.28318531)
#define GOLDEN_ANGLE	(2.39996323)
#define MAX_BLUR_SIZE	(20.0)
#define RADIUS_SCALE	(0.5)

public float ShadertoyNoise(vec2 uv)
{
	return frac(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

public float GetCircleOfConfusion(float depth, float focusPoint, float focusScale)
{
	// if depth is less than focusPoint, result will be negative. want to keep this
	// relationship so comparison of (signed) blur size is same as comparing depth.
	return clamp((1.0/focusPoint - 1.0/depth) * focusScale, -1.0, 1.0);
}

public float GetBlurSize(float depth, float focusPoint, float focusScale, float u_maxBlurSize)
{
	float circleOfConfusion = GetCircleOfConfusion(depth, focusPoint, focusScale);
	return circleOfConfusion * u_maxBlurSize;
}

public void GetColorAndBlurSize(
	Texture2D samplerColor,
	SamplerState samplerColorSampler,
	Texture2D samplerDepth,
	SamplerState samplerDepthSampler,
	vec2 texCoord,
	float focusPoint,
	float focusScale,
	out vec3 outColor,
	out float outBlurSize,
	float u_maxBlurSize,
	bool usePacked
) {
	if (usePacked)
	{
		vec4 colorAndBlurSize = texture2DLod(samplerColor, samplerColorSampler, texCoord, 0);
		vec3 color = colorAndBlurSize.xyz;
		float blurSize = colorAndBlurSize.w;

		outColor = color;
		outBlurSize = blurSize;
	}
	else
	{
		vec3 color = texture2DLod(samplerColor, samplerColorSampler, texCoord, 0).xyz;
		float depth = texture2DLod(samplerDepth, samplerDepthSampler, texCoord, 0).x;
		float blurSize = GetBlurSize(depth, focusPoint, focusScale, u_maxBlurSize);

		outColor = color;
		outBlurSize = blurSize;
	}
}

public float BokehShapeFromAngle(float lobeCount, float radiusMin, float radiusDelta2x, float rotation, float angle)
{
	// don't shape for 0, 1 blades...
	if (lobeCount <= 1.0f)
	{
		return 1.0f;
	}

	// divide edge into some number of lobes
	float invPeriod = lobeCount / (2.0 * 3.1415926);
	float periodFraction = frac(angle * invPeriod + rotation);

	// apply triangle shape to each lobe to approximate blades of a camera aperture
	periodFraction = abs(periodFraction - 0.5);
	return periodFraction*radiusDelta2x + radiusMin;
}

public vec4 DepthOfField(
	Texture2D samplerColor,
	SamplerState samplerColorSampler,
	Texture2D samplerDepth,
	SamplerState samplerDepthSampler,
	vec2 texCoord,
	float focusPoint,
	float focusScale,
	float u_maxBlurSize,
	float u_radiusScale,
	float u_frameIdx,
	float u_lobeCount,
	float u_lobeRadiusMin,
	float u_lobeRadiusDelta2x,
	float u_lobeRotation,
	vec4 u_viewRect,
	vec4 u_viewTexel,
	bool usePacked
) {
	vec3 color;
	float centerSize;
	GetColorAndBlurSize(
		samplerColor,
		samplerColorSampler,
		samplerDepth,
		samplerDepthSampler,
		texCoord,
		focusPoint,
		focusScale,
		/*out*/color,
		/*out*/centerSize,
		u_maxBlurSize,
		usePacked);
	float absCenterSize = abs(centerSize);

	// as sample count gets lower, visible banding. disrupt with noise.
	// use a better random/noise/dither function than this..
	vec2 pixelCoord = texCoord.xy * u_viewRect.zw;
	float random = ShadertoyNoise(pixelCoord + vec2(314.0, 159.0)*u_frameIdx);
	float theta = random * TWO_PI;
	float thetaStep = GOLDEN_ANGLE;

	float total = 1.0;
	float totalSampleSize = 0.0;
	float loopValue = u_radiusScale;
	float loopEnd = u_maxBlurSize;

	while (loopValue < loopEnd)
	{
		float radius = loopValue;
		float shapeScale = BokehShapeFromAngle(
			u_lobeCount,
			u_lobeRadiusMin,
			u_lobeRadiusDelta2x,
			u_lobeRotation,
			theta);
		vec2 spiralCoord = texCoord + vec2(cos(theta), sin(theta)) * u_viewTexel.xy * (radius * shapeScale);

		vec3 sampleColor;
		float sampleSize;
		GetColorAndBlurSize(
			samplerColor,
			samplerColorSampler,
			samplerDepth,
			samplerDepthSampler,
			spiralCoord,
			focusPoint,
			focusScale,
			/*out*/sampleColor,
			/*out*/sampleSize,
			u_maxBlurSize,
			usePacked);
		float absSampleSize = abs(sampleSize);

		// using signed sample size as proxy for depth comparison
		if (sampleSize > centerSize)
		{
			absSampleSize = clamp(absSampleSize, 0.0, absCenterSize*2.0);
		}
		float m = smoothstep(radius-0.5, radius+0.5, absSampleSize);
		color += mix(color/total, sampleColor, m);
		totalSampleSize += absSampleSize;
		total += 1.0;
		theta += thetaStep;

		loopValue += (u_radiusScale/loopValue);
	}

	color *= 1.0/total;
	float averageSampleSize = totalSampleSize / (total-1.0);
	return vec4(color, averageSampleSize);
}
