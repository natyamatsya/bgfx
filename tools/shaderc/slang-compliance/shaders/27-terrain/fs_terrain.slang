// 1-to-1 Slang port of examples/27-terrain fs_terrain.sc.
import bgfx_shader;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
	vec3 v_position  : TEXCOORD1;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return vec4(input.v_texcoord0.x, input.v_texcoord0.y, input.v_position.y / 50.0, 1.0);
}
