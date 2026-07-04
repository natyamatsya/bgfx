// 1-to-1 Slang port of examples/31-rsm fs_rsm_lbuffer.sc.
// Accumulates one point light into the light buffer: reconstructs world position from
// the G-buffer depth, decodes the G-buffer normal, and applies a linear-falloff point
// light. gl_FragCoord -> SV_Position input; u_viewTexel is auto-provided.
import bgfx_shader;
import shaderlib; // toClipSpaceDepth, clipToWorld

Texture2D    s_normal        : register(t0); // Normal output from gbuffer
SamplerState s_normalSampler : register(s0);
Texture2D    s_depth         : register(t1); // Depth output from gbuffer
SamplerState s_depthSampler  : register(s1);

uniform mat4 u_invMvp;

struct V2F
{
	vec4 gl_FragCoord       : SV_Position;
	vec4 v_lightCenterScale : TEXCOORD2;
	vec4 v_color0           : COLOR0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.gl_FragCoord.xy * u_viewTexel.xy;

	// Get world position
	float deviceDepth = texture2D(s_depth, s_depthSampler, texCoord).x;
	float depth       = toClipSpaceDepth(deviceDepth);

	vec3 clip = vec3(texCoord * 2.0 - 1.0, depth);
	clip.y = -clip.y; // !BGFX_SHADER_LANGUAGE_GLSL
	vec3 wpos = clipToWorld(u_invMvp, clip);

	// Get normal from its map, and decompress
	vec3 n  = texture2D(s_normal, s_normalSampler, texCoord).xyz*2.0-1.0;

	// Do lighting
	vec3 pointToLight = input.v_lightCenterScale.xyz-wpos;
	float lightLen = sqrt(dot(pointToLight, pointToLight));

	float lightFalloff;

	if (lightLen > input.v_lightCenterScale.w)
		lightFalloff = 0.0;
	else
		lightFalloff = 1.0-(lightLen/input.v_lightCenterScale.w);  // Linear falloff for light (could use dist sq if you want)

	vec3 l = normalize(pointToLight)*lightFalloff;

	vec4 fragColor;
	fragColor.xyz = input.v_color0.xyz * max(0.0, dot(n,l));
	fragColor.w = 1.0;
	return fragColor;
}
