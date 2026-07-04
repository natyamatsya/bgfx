// 1-to-1 Slang port of examples/21-deferred fs_deferred_light_ta.sc.
// SAMPLER2DARRAY(s_normal, 0) -> Texture2DArray + SamplerState. blinn/lit/calcLight
// from the example's common.sh (import common); clipToWorld is a shaderlib.sh helper
// (import shaderlib). u_view is auto-provided.
import bgfx_shader;
import shaderlib; // decodeNormalUint, toClipSpaceDepth, clipToWorld
import common;    // blinn, lit, calcLight

Texture2DArray s_normal        : register(t0);
SamplerState   s_normalSampler : register(s0);
Texture2D      s_depth         : register(t1);
SamplerState   s_depthSampler  : register(s1);

vec4 u_lightPosRadius[1];
vec4 u_lightRgbInnerR[1];
mat4 u_mtx;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3  normal      = decodeNormalUint(s_normal.Sample(s_normalSampler, vec3(input.v_texcoord0, 1.0) ).xyz);
	float deviceDepth = texture2D(s_depth, s_depthSampler, input.v_texcoord0).x;
	float depth       = toClipSpaceDepth(deviceDepth);

	vec3 clip = vec3(input.v_texcoord0 * 2.0 - 1.0, depth);
	clip.y = -clip.y; // !BGFX_SHADER_LANGUAGE_GLSL
	vec3 wpos = clipToWorld(u_mtx, clip);

	vec3 view = mul(u_view, vec4(wpos, 0.0) ).xyz;
	view = -normalize(view);

	vec3 lightColor = calcLight(wpos, normal, view, u_lightPosRadius[0].xyz, u_lightPosRadius[0].w, u_lightRgbInnerR[0].xyz, u_lightRgbInnerR[0].w);

	vec4 fragColor;
	fragColor.xyz = toGamma(lightColor.xyz);
	fragColor.w = 1.0;
	return fragColor;
}
