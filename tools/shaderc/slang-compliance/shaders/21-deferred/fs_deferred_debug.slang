// 1-to-1 Slang port of examples/21-deferred fs_deferred_debug.sc.
import bgfx_shader;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return texture2D(s_texColor, s_texColorSampler, input.v_texcoord0);
}
