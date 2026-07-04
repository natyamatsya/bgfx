// 1-to-1 Slang port of examples/19-oit fs_oit_wb_separate_blit.sc (two SAMPLER2D).
import bgfx_shader;

Texture2D    s_texColor0        : register(t0);
SamplerState s_texColor0Sampler : register(s0);
Texture2D    s_texColor1        : register(t1);
SamplerState s_texColor1Sampler : register(s1);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	vec4  accum   = texture2D(s_texColor0, s_texColor0Sampler, input.v_texcoord0);
	float opacity = accum.w;
	float weight  = texture2D(s_texColor1, s_texColor1Sampler, input.v_texcoord0).x;
	return vec4(accum.xyz / clamp(weight, 1e-4, 5e4), opacity);
}
