// Slang port of examples/54-s2h/fs_s2h.sc.
import bgfx_shader;
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
	ContextGather ui;
	s2h_init(ui, s2h_getPixelCoord(input.pos.xy) );
	s2h_setCursor(ui, vec2(16.0f, 16.0f) );
	s2h_setScale(ui, 2.0f);

	// s2h_printTxt accepts up to six characters per call.
	s2h_printTxt(ui, _H, _e, _l, _l, _o, _SPACE);
	s2h_printTxt(ui, _W, _o, _r, _l, _d);

	vec4 background = vec4(0.02f, 0.02f, 0.02f, 1.0f);
	vec4 linearColor = background * (1.0f - ui.dstColor.a) + ui.dstColor;
	return vec4(s2h_accurateLinearToSRGB(linearColor.rgb), linearColor.a);
}
