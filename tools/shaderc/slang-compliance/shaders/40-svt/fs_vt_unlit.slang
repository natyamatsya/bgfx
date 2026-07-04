// 1-to-1 Slang port of examples/40-svt fs_vt_unlit.sc. The virtualtexture.sh helpers +
// resources are ported once to the co-located virtualtexture.sh.slang and imported here.
import bgfx_shader;
import virtualtexture;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	return VirtualTexture(input.v_texcoord0.xy);
}
