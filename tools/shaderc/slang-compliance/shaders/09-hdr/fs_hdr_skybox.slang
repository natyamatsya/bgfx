// 1-to-1 Slang port of examples/09-hdr fs_hdr_skybox.sc (cubemap: SAMPLERCUBE + textureCube).
// encodeRGBE8 comes from examples/common/shaderlib.sh (import shaderlib).
import bgfx_shader;
import shaderlib;

TextureCube  s_texCube        : register(t0);
SamplerState s_texCubeSampler : register(s0);

float4x4 u_mtx;

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 dir = vec3(input.v_texcoord0*2.0 - 1.0, 1.0);
	dir = normalize(mul(u_mtx, vec4(dir, 0.0) ).xyz);
	return encodeRGBE8(textureCube(s_texCube, s_texCubeSampler, dir).xyz);
}
