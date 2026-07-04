// 1-to-1 Slang port of examples/21-deferred fs_deferred_debug_line.sc.
import bgfx_shader;

struct V2F
{
	vec4 v_color0 : COLOR0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return input.v_color0;
}
