// 1-to-1 Slang port of examples/08-update fs_update.sc.
// SAMPLERCUBE(s_texCube, 0) -> TextureCube + SamplerState; textureCube -> .Sample.
import bgfx_shader;

// SAMPLERCUBE(s_texCube, 0)
TextureCube  s_texCube        : register(t0);
SamplerState s_texCubeSampler : register(s0);

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return textureCube(s_texCube, s_texCubeSampler, input.v_texcoord0);
}
