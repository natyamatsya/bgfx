// 1-to-1 Slang port of examples/36-sky fs_sky_landscape.sc.
// interleavedGradientNoise and toLinear(float) are defined inline in the .sc body
// -> kept inline here. toGamma comes from the central bgfx_shader.
import bgfx_shader;

Texture2D    s_texLightmap        : register(t0);
SamplerState s_texLightmapSampler : register(s0);

vec4 u_sunDirection;
vec4 u_sunLuminance;
vec4 u_skyLuminance;
vec4 u_parameters;

struct V2F
{
	vec4 gl_FragCoord : SV_Position;
	vec3 v_normal     : NORMAL;
	vec2 v_texcoord0  : TEXCOORD0;
};

// Interleaved gradient noise (better for Metal)
// Reference: http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare
float interleavedGradientNoise(vec2 screenPos, float temporalFactor)
{
	vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
	vec2 coord = screenPos + fract(temporalFactor) * vec2_splat(13.0);
	return fract(magic.z * fract(dot(coord, magic.xy)));
}

float toLinear(float _rgb)
{
	return pow(abs(_rgb), 2.2);
}

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	vec3 normal = normalize(input.v_normal);

	float occulsion = toLinear(texture2D(s_texLightmap, s_texLightmapSampler, input.v_texcoord0).r);

	vec3 skyDirection = vec3(0.0, 0.0, 1.0);

	float diffuseSun = max(0.0, dot(normal, normalize(u_sunDirection.xyz)));
	float diffuseSky = 1.0 + 0.5 * dot(normal, skyDirection);

	vec3 color = diffuseSun * u_sunLuminance.rgb + (diffuseSky * u_skyLuminance.rgb + 0.01) * occulsion;
	color *= 0.5;

	float4 gl_FragColor;
	gl_FragColor.xyz = color * u_parameters.z;
	gl_FragColor.w = 1.0;

	float dither = interleavedGradientNoise(input.gl_FragCoord.xy, u_parameters.w);
	dither = (dither - 0.5) / 255.0;

	gl_FragColor.xyz = toGamma(gl_FragColor.xyz) + vec3_splat(dither);

	return gl_FragColor;
}
