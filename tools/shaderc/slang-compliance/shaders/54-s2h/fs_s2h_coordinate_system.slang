// Slang port of examples/54-s2h/fs_s2h_coordinate_system.sc.
// The stock file notes it is a port of ShaderToHuman-bgfx Features/2D_CoordinateSystem.hlsl.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
#include "s2h_bgfx.h"
#include "s2h/s2h.hlsl"

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 background = vec4(0.01f, 0.01f, 0.1f, 1.0f);

	ContextGather ui;
	vec2 pixelPosition = floor(s2h_getPixelCoord(input.pos.xy) ) + 0.5f;
	s2h_init(ui, pixelPosition);
	s2h_setScale(ui, 2);
	s2h_setCursor(ui, vec2(10.0f, 10.0f) );

	s2h_coordinateSystem(ui, vec2(50.0f, 130.0f), vec4(-30.0f, -30.0f, 250.0f, 250.0f), 1.0f, 20.0f, vec4(1.0f, 1.0f, 1.0f, 0.25f), 0);
	ui.lineWidth = 1.0f;
	s2h_coordinateSystem(ui, vec2(440.0f, 150.0f), vec4(-10.0f, -120.0f, 150.0f, 10.0f), 1.0f, 20.0f, vec4(1.0f, 1.0f, 1.0f, 0.25f), 3);

	s2h_printTxt(ui, _s, _2, _h, _UNDERSCORE);
	s2h_printTxt(ui, _c, _o, _o, _r, _d, _i);
	s2h_printTxt(ui, _n, _a, _t, _e, _S, _y);
	s2h_printTxt(ui, _s, _t, _e, _m);

	return mix(background, vec4(ui.dstColor.rgb, 1.0f), ui.dstColor.a);
}
