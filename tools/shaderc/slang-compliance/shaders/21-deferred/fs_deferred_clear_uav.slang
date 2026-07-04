// 1-to-1 Slang port of examples/21-deferred fs_deferred_clear_uav.sc.
// IMAGE2D_RW(i_light, rgba8, 2) -> a read-write storage image; gl_FragCoord -> SV_Position.
import bgfx_shader;

[[vk::image_format("rgba8")]]
RWTexture2D<vec4> i_light : register(u2);

struct V2F
{
	vec4 gl_FragCoord : SV_Position;
	vec2 v_texcoord0  : TEXCOORD0;
};

[shader("fragment")]
void fragmentMain(V2F input)
{
	ivec2 coord = ivec2(input.gl_FragCoord.xy);
	i_light[coord] = vec4(0.0, 0.0, 0.0, 0.0);
}
