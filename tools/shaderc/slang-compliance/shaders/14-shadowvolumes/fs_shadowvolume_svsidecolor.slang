// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_svsidecolor.sc.
import bgfx_shader;

vec4 u_color;

struct V2F
{
	float4 pos : SV_Position;
	float  v_k : FOG;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 color;
	color.xyz = u_color.xyz;
	color.w   = 0.98;
	return color;
}
