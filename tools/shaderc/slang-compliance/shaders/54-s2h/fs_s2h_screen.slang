// Slang port of examples/54-s2h/fs_s2h_screen.sc.
// The stock file notes it is a port of ShaderToHuman-bgfx HelloScreenVSPS/HelloWorldPS.hlsl.
// u_viewRect is a bgfx predefined uniform, so it is used without being declared.
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
	vec2 pxPos = s2h_getPixelCoord(input.pos.xy);
	vec2 dimensions = u_viewRect.zw;
	vec2 uv = pxPos / dimensions;

	ContextGather ui;
	s2h_init(ui, pxPos);
	s2h_setCursor(ui, vec2(10.0f, 10.0f) );
	s2h_setScale(ui, 3.0f);
	s2h_printTxt(ui, _H, _e, _l, _l, _o);
	s2h_printLF(ui);
	s2h_printTxt(ui, _S, _c, _r, _e, _e);
	s2h_printTxt(ui, _n);
	s2h_drawSRGBRamp(ui, vec2(10.0f, 100.0f) );

	vec4 background = vec4(uv.x, uv.y, 0.0f, 1.0f);
	return mix(background, vec4(ui.dstColor.rgb, 1.0f), ui.dstColor.a);
}
