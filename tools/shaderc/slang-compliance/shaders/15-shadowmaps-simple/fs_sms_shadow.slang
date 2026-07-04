// 1-to-1 Slang port of examples/15-shadowmaps-simple fs_sms_shadow.sc
// (shadow-map generation pass: color output is unused, only hardware depth matters).
import bgfx_shader;

[shader("fragment")]
vec4 fragmentMain() : SV_Target
{
	return vec4_splat(0.0);
}
