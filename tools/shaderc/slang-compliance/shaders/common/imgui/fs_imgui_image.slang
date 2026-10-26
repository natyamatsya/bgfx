// 1-to-1 Slang port of examples/common/imgui fs_imgui_image.sc -- ImGui's image widget, with
// the 55-hdr10 output transform applied to its colour.
//
// Copyright 2014 Dario Manesku. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
import bgfx_shader;
import imgui_output;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

// u_imguiOutput first, as in the stock .sc, which includes imgui_output.sh before declaring
// u_imageLodEnabled.
vec4 u_imguiOutput;
vec4 u_imageLodEnabled;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	// u_imageLod = u_imageLodEnabled.x, u_imageEnabled = u_imageLodEnabled.y
	vec3 color = texture2DLod(s_texColor, s_texColorSampler, input.v_texcoord0, u_imageLodEnabled.x).xyz;
	float alpha = 0.2 + 0.8*u_imageLodEnabled.y;
	return vec4(imguiOutput(color, u_imguiOutput), alpha);
}
