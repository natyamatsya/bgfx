// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_svbackblank.sc.
import bgfx_shader;

[shader("fragment")]
vec4 fragmentMain() : SV_Target
{
	return vec4_splat(1.0);
}
