// 1-to-1 Slang port of examples/common/imgui fs_ocornut_imgui.sc -- ImGui's draw-list shader,
// with the 55-hdr10 output transform applied to its colour.
import bgfx_shader;
import imgui_output;

Texture2D    s_tex        : register(t0);
SamplerState s_texSampler : register(s0);

vec4 u_imguiOutput;

struct V2F
{
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 texel = texture2D(s_tex, s_texSampler, input.v_texcoord0);
	vec4 color = texel * input.v_color0;
	return vec4(imguiOutput(color.xyz, u_imguiOutput), color.w);
}
