// 1-to-1 Slang port of examples/19-oit fs_oit.sc.
import bgfx_shader;

float4 u_color;

struct V2F
{
	vec4 v_pos : TEXCOORD4;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	return u_color;
}
