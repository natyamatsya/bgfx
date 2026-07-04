// 1-to-1 Slang port of examples/36-sky fs_sky_color_banding_fix.sc.
// interleavedGradientNoise is defined inline in the .sc body -> kept inline here.
// toGamma comes from the central bgfx_shader.
import bgfx_shader;

vec4 u_parameters; // x - sun size, y - sun bloom, z - exposition, w - time
vec4 u_sunDirection;
// u_sunLuminance is declared in the .sc but unused; glslang strips it, so it is omitted here.

struct V2F
{
	vec4 gl_FragCoord : SV_Position;
	vec2 v_screenPos  : TEXCOORD0;
	vec3 v_skyColor   : TEXCOORD1;
	vec3 v_viewDir    : TEXCOORD2;
};

// Interleaved gradient noise (better for Metal)
// Reference: http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare
float interleavedGradientNoise(vec2 screenPos, float temporalFactor)
{
	vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
	vec2 coord = screenPos + fract(temporalFactor) * vec2_splat(13.0);
	return fract(magic.z * fract(dot(coord, magic.xy)));
}

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	float size2 = u_parameters.x * u_parameters.x;

	vec3 lightDir = normalize(u_sunDirection.xyz);
	float distance = 2.0 * (1.0 - dot(normalize(input.v_viewDir), lightDir));
	float sun = exp(-distance / u_parameters.y / size2) + step(distance, size2);
	float sun2 = min(sun * sun, 1.0);
	vec3 color = input.v_skyColor + sun2;
	color = toGamma(color);

	float dither = interleavedGradientNoise(input.gl_FragCoord.xy, u_parameters.w);
	dither = (dither - 0.5) / 255.0;
	color += vec3_splat(dither);

	return vec4(color, 1.0);
}
