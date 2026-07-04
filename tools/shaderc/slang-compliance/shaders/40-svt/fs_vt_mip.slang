// 1-to-1 Slang port of examples/40-svt fs_vt_mip.sc. The virtualtexture.sh helpers +
// resources are ported once to the co-located virtualtexture.sh.slang and imported here.
// import does not carry the .sh's #define aliases, so the ones referenced directly by this
// entry point are re-declared against the imported public u_vt_settings_* uniforms.
import bgfx_shader;
import virtualtexture;

#define VirtualTextureSize u_vt_settings_1.x
#define MipBias            u_vt_settings_2.x
#define PageTableSize      u_vt_settings_2.y

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	float mipCount = log2(PageTableSize);
	float mip = floor(MipLevel(input.v_texcoord0.xy, VirtualTextureSize) - MipBias);
	mip = clamp(mip, 0, mipCount);
	vec2 offset = floor(input.v_texcoord0.xy * PageTableSize);
	return vec4(floor(vec3(offset / exp2(mip), mip)) / 255.0, 1.0);
}
