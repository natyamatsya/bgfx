// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_svfrontblank.sc.
import bgfx_shader;

[shader("fragment")]
vec4 fragmentMain() : SV_Target
{
	return vec4(vec3_splat(0.0), 1.0);
}
