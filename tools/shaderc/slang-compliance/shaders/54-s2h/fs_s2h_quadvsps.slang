// Slang port of examples/54-s2h/fs_s2h_quadvsps.sc.
// u_viewRect is a bgfx predefined uniform, so it is used without being declared.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
#include "s2h_bgfx.h"
#include "s2h/s2h.hlsl"

vec4 u_s2hTime;
vec4 u_s2hMouse;

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 edge = min(input.v_texcoord0, 1.0f - input.v_texcoord0);
	float border = 1.0f - smoothstep(0.008f, 0.018f, min(edge.x, edge.y) );
	vec3 color = mix(vec3(0.03f, 0.04f, 0.08f), vec3(1.0f, 0.0f, 1.0f), border * 0.4f);

	ContextGather ui;
	s2h_init(ui, s2h_getPixelCoord(input.pos.xy) );
	s2h_setCursor(ui, vec2(10.0f, 10.0f) );
	s2h_setScale(ui, 2);
	s2h_printTxt(ui, _Q, _u, _a, _d);
	s2h_printTxt(ui, _V, _S, _P, _S);
	s2h_printLF(ui);
	s2h_printLF(ui);
	vec2 mouseUv = u_s2hMouse.xy / u_viewRect.zw;
	s2h_printTxt(ui, _u, _v, _COLON, _SPACE);
	s2h_printFloat(ui, mouseUv.x); s2h_printTxt(ui, _COMMA); s2h_printFloat(ui, mouseUv.y);
	s2h_printLF(ui);
	s2h_printTxt(ui, _t, _i, _m, _e, _COLON, _SPACE); s2h_printFloat(ui, u_s2hTime.x);

	color = mix(color, ui.dstColor.rgb, ui.dstColor.a);
	return vec4(color, 1.0f);
}
