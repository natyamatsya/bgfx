// 1-to-1 Slang port of examples/21-deferred fs_deferred_debug_ta.sc.
// SAMPLER2DARRAY(s_texColor, 0) -> Texture2DArray + SamplerState.
import bgfx_shader;

Texture2DArray s_texColor        : register(t0);
SamplerState   s_texColorSampler : register(s0);

vec4 u_layer;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return s_texColor.Sample(s_texColorSampler, vec3(input.v_texcoord0, u_layer.x) );
}
