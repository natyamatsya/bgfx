// 1-to-1 Slang port of examples/30-picking fs_picking_id.sc.
import bgfx_shader;

vec4 u_id;

struct V2F
{
	vec3 v_pos    : TEXCOORD1;
	vec3 v_view   : TEXCOORD2;
	vec3 v_normal : NORMAL;
	vec4 v_color0 : COLOR0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 fragColor;
	fragColor.xyz = u_id.xyz; // This is dumb, should use u8 texture
	fragColor.w = 1.0;
	return fragColor;
}
