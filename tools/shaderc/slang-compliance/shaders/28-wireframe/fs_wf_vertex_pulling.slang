// 1-to-1 Slang port of examples/28-wireframe fs_wf_vertex_pulling.sc.
// Passes the interpolated wireframe color straight through; declares no uniforms.
import bgfx_shader;

struct V2F
{
	vec4 v_color : COLOR0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return input.v_color;
}
