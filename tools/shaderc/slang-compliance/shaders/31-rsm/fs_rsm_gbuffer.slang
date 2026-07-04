// 1-to-1 Slang port of examples/31-rsm fs_rsm_gbuffer.sc.
// MRT G-buffer: gl_FragData[0] = normal (already [0,1] compressed), gl_FragData[1] =
// tint color -> a struct of SV_Target0/SV_Target1.
import bgfx_shader;

uniform vec4 u_tint;

struct V2F
{
	vec4 pos      : SV_Position;
	vec3 v_normal : NORMAL;
};

struct GBuffer
{
	vec4 gbuffer0 : SV_Target0;
	vec4 gbuffer1 : SV_Target1;
};

[shader("fragment")]
GBuffer fragmentMain(V2F input)
{
	vec3 normalWorldSpace = input.v_normal;

	GBuffer output;
	// Write normal
	output.gbuffer0.xyz = normalWorldSpace.xyz; // Normal is already compressed to [0,1] so can fit in gbuffer
	output.gbuffer0.w = 0.0;

	// Write color
	output.gbuffer1 = u_tint;
	return output;
}
