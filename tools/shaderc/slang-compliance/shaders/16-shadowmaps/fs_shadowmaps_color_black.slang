// 1-to-1 Slang port of examples/16-shadowmaps/fs_shadowmaps_color_black.sc
import bgfx_shader;

[shader("fragment")]
vec4 fragmentMain() : SV_Target
{
	return vec4(0.0, 0.0, 0.0, 0.0);
}
