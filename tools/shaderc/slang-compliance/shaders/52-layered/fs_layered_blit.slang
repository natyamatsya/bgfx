// Slang port of examples/52-layered/fs_layered_blit.sc.
// SAMPLER2DARRAY(s_texColor, 0) -> Texture2DArray + SamplerState; texture2DArray -> .Sample.
import bgfx_shader;

Texture2DArray s_texColor        : register(t0);
SamplerState   s_texColorSampler : register(s0);

float4 u_eyeParams; // x = array layer to sample

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	return s_texColor.Sample(s_texColorSampler, vec3(input.v_texcoord0, u_eyeParams.x) );
}
