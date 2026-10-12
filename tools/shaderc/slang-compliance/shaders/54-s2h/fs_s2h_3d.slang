// Slang port of examples/54-s2h/fs_s2h_3d.sc -- a self-contained fragment-renderer port of
// the S2H Features/3D_example.hlsl. Pulls in the library's 3D module.
// u_viewRect is a bgfx predefined uniform, so it is used without being declared.
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix
#include "s2h_bgfx.h"
#include "s2h/s2h.hlsl"
#include "s2h/s2h_3d.hlsl"

vec4 u_s2hTime;

struct V2F
{
	vec4 pos         : SV_Position;
	vec4 v_color0    : COLOR0;
	vec2 v_texcoord0 : TEXCOORD0;
};

void scene(inout Context3D _context)
{
	vec3 offset = vec3(0.0f, -1.0f, 0.0f);
	s2h_drawCheckerBoard(_context, offset);
	s2h_drawLineWS(_context, vec3(-1.0f, 2.0f,  1.0f) + offset, vec3(1.0f, 2.0f,  1.0f) + offset, vec4(1.0f, 1.0f, 0.0f, 1.0f), 0.09f);
	s2h_drawLineWS(_context, vec3(-1.0f, 2.0f, -1.0f) + offset, vec3(1.0f, 2.0f, -1.0f) + offset, vec4(1.0f, 1.0f, 0.0f, 1.0f), 0.09f);
	s2h_drawLineWS(_context, vec3(-1.0f, 2.0f, -1.0f) + offset, vec3(-1.0f, 2.0f, 1.0f) + offset, vec4(1.0f, 1.0f, 0.0f, 1.0f), 0.09f);
	s2h_drawLineWS(_context, vec3( 1.0f, 2.0f, -1.0f) + offset, vec3( 1.0f, 2.0f, 1.0f) + offset, vec4(1.0f, 1.0f, 0.0f, 1.0f), 0.09f);
}

vec3 safeNormalize(vec3 _value)
{
	return _value / max(length(_value), 0.0001f);
}

mat4 lookAt(vec3 _eye, vec3 _target, vec3 _up)
{
	vec3 zaxis = safeNormalize(_target - _eye);
	vec3 xaxis = safeNormalize(cross(_up, zaxis) );
	vec3 yaxis = cross(zaxis, xaxis);
	// The stock shader builds this as rows + transpose on HLSL and as columns on GLSL --
	// the same matrix either way. mtxFromCols is the Slang spelling of the column form.
	return mtxFromCols(vec4(xaxis, 0.0f), vec4(yaxis, 0.0f), vec4(zaxis, 0.0f), vec4(_eye, 1.0f) );
}

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 resolution = u_viewRect.zw;
	vec2 pixel = s2h_getPixelCoord(input.pos.xy);
	vec2 uv = pixel / resolution;
	vec2 screen = uv * 2.0f - 1.0f;
	screen.x *= resolution.x / resolution.y;
	screen.y = -screen.y;

	float orbit = u_s2hTime.x * 0.35f;
	vec3 cameraPosition = vec3(sin(orbit) * 5.0f, 2.5f, cos(orbit) * 5.0f);
	vec3 cameraForward = safeNormalize(vec3(0.0f, 0.4f, 0.0f) - cameraPosition);
	vec3 cameraRight = safeNormalize(cross(vec3(0.0f, 1.0f, 0.0f), cameraForward) );
	vec3 cameraUp = cross(cameraForward, cameraRight);
	vec3 rayDirection = safeNormalize(cameraForward + screen.x * cameraRight * 0.8f + screen.y * cameraUp * 0.8f);

	Context3D context;
	s2h_init(context, cameraPosition, rayDirection);
	context.dstColor = vec4(safeNormalize(rayDirection * 0.5f + 0.5f) * 0.25f, 1.0f);
	sceneWithShadows(context);
	scene(context);

	float s = sin(u_s2hTime.x) * 3.0f;
	float c = cos(u_s2hTime.x) * 3.0f;
	s2h_drawBasis(context, lookAt(vec3(s, 1.0f, c), vec3(0.0f, 1.0f, 0.0f), vec3(0.0f, 1.0f, 0.0f) ), 1.0f);

	ContextGather ui;
	s2h_init(ui, pixel);
	s2h_setCursor(ui, vec2(10.0f, 10.0f) );
	s2h_setScale(ui, 2);
	s2h_printTxt(ui, _P, _o, _s, _COLON);
	s2h_printFloat(ui, cameraPosition.x); s2h_printTxt(ui, _COMMA);
	s2h_printFloat(ui, cameraPosition.y); s2h_printTxt(ui, _COMMA);
	s2h_printFloat(ui, cameraPosition.z);

	vec3 color = mix(vec3(0.0f, 0.0f, 0.0f), context.dstColor.rgb, context.dstColor.a);
	color = color * (1.0f - ui.dstColor.a) + ui.dstColor.rgb;
	return vec4(s2h_accurateLinearToSRGB(color), 1.0f);
}
