// 1-to-1 Slang port of examples/46-fsr fs_fsr_copy_linear_to_gamma.sc.
// Stock includes common.sh only for toGamma; no loose uniforms are declared.
import bgfx_shader;

Texture2D    s_color        : register(t0);
SamplerState s_colorSampler : register(s0);

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 texCoord = input.v_texcoord0;
	vec4 linearColor = texture2D(s_color, s_colorSampler, texCoord);

	// this pass is writing directly out to backbuffer, convert from linear to gamma
	vec4 color = vec4(toGamma(linearColor.xyz), linearColor.w);

	return color;
}
