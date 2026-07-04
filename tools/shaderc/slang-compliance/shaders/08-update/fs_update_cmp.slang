// 1-to-1 Slang port of examples/08-update fs_update_cmp.sc.
// SAMPLER2D(s_texColor, 0) -> Texture2D + SamplerState; texture2D -> .Sample.
import bgfx_shader;

// SAMPLER2D(s_texColor, 0)
Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return texture2D(s_texColor, s_texColorSampler, input.v_texcoord0.xy * 0.5 + 0.5);
}
