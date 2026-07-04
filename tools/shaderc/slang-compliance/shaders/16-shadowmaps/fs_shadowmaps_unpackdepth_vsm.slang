// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_unpackdepth_vsm.sc
import bgfx_shader;
import shaderlib; // unpackRgbaToFloat, unpackHalfFloat

Texture2D    s_shadowMap0        : register(t4);
SamplerState s_shadowMap0Sampler : register(s4);

float4 u_params2; // u_depthValuePow = u_params2.x

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 val = texture2D(s_shadowMap0, s_shadowMap0Sampler, input.v_texcoord0);
	float depth = unpackHalfFloat(val.rg);
	vec3 rgba = pow(vec3_splat(depth), vec3_splat(u_params2.x) );
	return vec4(rgba, 1.0);
}
