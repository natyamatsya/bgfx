// Slang port of examples/54-s2h/fs_s2h_zoom2d.sc.
// The stock file notes it is adapted from ShaderToHuman-bgfx Zoom2D/Render.hlsl.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
#include "s2h_bgfx.h"
#include "s2h/s2h.hlsl"

vec4 u_s2hZoom;

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

float grid(vec2 _position, float _scale)
{
	vec2 local = abs(frac(_position / 20.0f) - 0.5f);
	float gridLine = 1.0f - smoothstep(0.46f, 0.50f, max(local.x, local.y) );
	return gridLine * saturate((_scale - 2.0f) / 6.0f);
}

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 pixel = s2h_getPixelCoord(input.pos.xy);
	float zoomScale = u_s2hZoom.z;
	vec2 zoomedPixel = (pixel + u_s2hZoom.xy) * zoomScale;
	vec2 snappedPixel = floor(zoomedPixel) + 0.5f;
	vec3 color = vec3(0.01f, 0.01f, 0.10f);
	color = mix(color, vec3(0.22f, 0.25f, 0.35f), grid(zoomedPixel, zoomScale) );

	ContextGather ui;
	s2h_init(ui, snappedPixel);
	s2h_setCursor(ui, vec2(10.0f, 10.0f) );
	s2h_coordinateSystem(ui, vec2(50.0f, 130.0f), vec4(-30.0f, -30.0f, 250.0f, 250.0f), 1.0f, 20.0f, vec4(1.0f, 1.0f, 1.0f, 0.25f), 0);
	ui.lineWidth = 1.0f;
	s2h_coordinateSystem(ui, vec2(340.0f, 120.0f), vec4(-10.0f, -100.0f, 150.0f, 10.0f), 1.0f, 20.0f, vec4(1.0f, 1.0f, 1.0f, 0.25f), 3);
	s2h_printTxt(ui, _c, _o, _o, _r, _d, _i);
	s2h_printTxt(ui, _n, _a, _t, _e, _S, _y);
	s2h_printTxt(ui, _s, _t, _e, _m);
	color = mix(color, ui.dstColor.rgb, ui.dstColor.a);

	ContextGather overlay;
	s2h_init(overlay, pixel);
	s2h_setCursor(overlay, vec2(10.0f, 480.0f) );
	overlay.textColor.rgb = vec3(1.0f, 1.0f, 0.1f);
	s2h_setScale(overlay, 2.0f);
	s2h_printTxt(overlay, _X, _Y, _COLON, _SPACE); s2h_printFloat(overlay, u_s2hZoom.x);
	s2h_printTxt(overlay, _SPACE); s2h_printFloat(overlay, u_s2hZoom.y); s2h_printLF(overlay);
	s2h_printTxt(overlay, _SPACE, _S, _COLON, _SPACE); s2h_printFloat(overlay, zoomScale); s2h_printLF(overlay);
	s2h_printLF(overlay);
	s2h_setScale(overlay, 1.0f);
	s2h_printTxt(overlay, _l, _e, _f, _t, _SPACE, _M);
	s2h_printTxt(overlay, _o, _u, _s, _e, _COLON, _SPACE);
	s2h_printTxt(overlay, _P, _a, _n); s2h_printLF(overlay);
	s2h_printTxt(overlay, _r, _i, _g, _h, _t, _SPACE);
	s2h_printTxt(overlay, _M, _o, _u, _s, _e, _COLON);
	s2h_printTxt(overlay, _SPACE, _S, _c, _a, _l, _e);
	color = mix(color, overlay.dstColor.rgb, overlay.dstColor.a);

	return vec4(color, 1.0f);
}
