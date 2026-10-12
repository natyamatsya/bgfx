// Slang port of examples/54-s2h/fs_s2h_clear.sc -- a self-contained fragment-renderer port
// of the S2H Features/Clear_example.hlsl. Pulls in the library's 3D module.
// u_viewRect is a bgfx predefined uniform, so it is used without being declared.
import bgfx_shader;
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

vec3 safeNormalize(vec3 _value)
{
	return _value / max(length(_value), 0.0001f);
}

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 resolution = u_viewRect.zw;
	vec2 fragmentPixel = s2h_getPixelCoord(input.pos.xy);
	vec2 pixel = floor(fragmentPixel);
	uvec2 gridPosition = uvec2(pixel) / 16u;
	bool checker = (gridPosition.x % 2u) == (gridPosition.y % 2u);
	vec3 fallbackColor = checker ? vec3(0.29f, 0.29f, 0.348f) : vec3(0.27f, 0.27f, 0.324f);

	vec2 screen = fragmentPixel / resolution * 2.0f - 1.0f;
	screen.x *= resolution.x / resolution.y;
	screen.y = -screen.y;
	float orbit = u_s2hTime.x * 0.2f;
	vec3 cameraPosition = vec3(sin(orbit) * 3.0f, 1.5f, cos(orbit) * 3.0f);
	vec3 forward = safeNormalize(vec3(0.0f, 0.4f, 0.0f) - cameraPosition);
	vec3 right = safeNormalize(cross(vec3(0.0f, 1.0f, 0.0f), forward) );
	vec3 up = cross(forward, right);
	vec3 rayDirection = safeNormalize(forward + screen.x * right * 0.8f + screen.y * up * 0.8f);

	Context3D context;
	s2h_init(context, cameraPosition, rayDirection);
	s2h_drawSkybox(context);
	vec3 color = context.dstColor.a > 0.0f ? context.dstColor.rgb : fallbackColor;
	return vec4(color, 1.0f);
}
