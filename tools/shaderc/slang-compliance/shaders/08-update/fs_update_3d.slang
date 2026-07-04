// 1-to-1 Slang port of examples/08-update fs_update_3d.sc.
// SAMPLER3D(s_texColor, 0) -> Texture3D + SamplerState; texture3D -> .Sample.
import bgfx_shader;

// SAMPLER3D(s_texColor, 0)
Texture3D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

uniform vec4 u_time;

struct V2F
{
	vec4 pos         : SV_Position;
	vec3 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 uvw = vec3(input.v_texcoord0.xy * 0.5 + 0.5, sin(u_time.x) * 0.5 + 0.5);
	return vec4_splat(s_texColor.Sample(s_texColorSampler, uvw).x);
}
