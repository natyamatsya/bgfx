// Slang port of examples/39-assao fs_assao_gbuffer.sc — gbuffer FS (MRT).
// gl_FragData[0..1] -> struct of SV_Target0/1. SAMPLER2D s_albedo.
import bgfx_shader;

Texture2D    s_albedo        : register(t0);
SamplerState s_albedoSampler : register(s0);

struct V2F
{
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
};

struct FSOutput
{
	vec4 target0 : SV_Target0;
	vec4 target1 : SV_Target1;
};

[shader("fragment")]
FSOutput fragmentMain(V2F input)
{
	FSOutput output;

	vec3 normalWorldSpace = input.v_normal;

	// Write normal
	output.target0.xyz = normalWorldSpace.xyz; // Normal is already compressed to [0,1] so can fit in gbuffer
	output.target0.w = 0.0;

	// Write color
	output.target1 = texture2D(s_albedo, s_albedoSampler, input.v_texcoord0);

	return output;
}
