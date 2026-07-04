// 1-to-1 Slang port of examples/21-deferred fs_deferred_geom.sc.
// MRT G-buffer: gl_FragData[0]/[1] -> a struct of SV_Target0/SV_Target1.
// u_invView is auto-provided.
import bgfx_shader;
import shaderlib; // encodeNormalUint

Texture2D    s_texColor         : register(t0);
SamplerState s_texColorSampler  : register(s0);
Texture2D    s_texNormal        : register(t1);
SamplerState s_texNormalSampler : register(s1);

struct V2F
{
	vec3 v_wpos      : TEXCOORD1;
	vec3 v_view      : TEXCOORD2;
	vec3 v_normal    : NORMAL;
	vec3 v_tangent   : TANGENT;
	vec3 v_bitangent : BINORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
};

struct GBuffer
{
	vec4 gbuffer0 : SV_Target0;
	vec4 gbuffer1 : SV_Target1;
};

[shader("fragment")]
GBuffer fragmentMain(V2F input)
{
	vec3 normal;
	normal.xy = texture2D(s_texNormal, s_texNormalSampler, input.v_texcoord0).xy * 2.0 - 1.0;
	normal.z  = sqrt(1.0 - dot(normal.xy, normal.xy) );

	mat3 tbn = mtxFromCols(
				normalize(input.v_tangent),
				normalize(input.v_bitangent),
				normalize(input.v_normal)
				);

	normal = normalize(mul(tbn, normal) );

	vec3 wnormal = normalize(mul(u_invView, vec4(normal, 0.0) ).xyz);

	GBuffer output;
	output.gbuffer0 = texture2D(s_texColor, s_texColorSampler, input.v_texcoord0);
	output.gbuffer1 = vec4(encodeNormalUint(wnormal), 1.0);
	return output;
}
