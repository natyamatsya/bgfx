// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_svfrontcolor.sc.
import bgfx_shader;

vec4 u_color;

[shader("fragment")]
vec4 fragmentMain() : SV_Target
{
	vec4 color;
	color.xyz = u_color.xyz;
	color.w   = 0.98;
	return color;
}
