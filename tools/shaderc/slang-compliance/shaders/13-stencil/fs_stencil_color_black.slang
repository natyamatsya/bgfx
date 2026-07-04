// 1-to-1 Slang port of examples/13-stencil fs_stencil_color_black.sc.
import bgfx_shader;

[shader("fragment")]
float4 fragmentMain() : SV_Target
{
	return vec4(0.0, 0.0, 0.0, 0.0);
}
