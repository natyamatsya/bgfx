// 1-to-1 Slang port of examples/12-lod fs_tree.sc (per-stage; the VS declares a
// different uniform set). Two samplers, one custom uniform (u_stipple); u_viewRect is
// predefined and auto-declared. blinn is defined inline in the .sc body, so it stays
// inline here. toLinear/toGamma come from bgfx_shader.
import bgfx_shader;

Texture2D    s_texColor          : register(t0);
SamplerState s_texColorSampler   : register(s0);
Texture2D    s_texStipple        : register(t1);
SamplerState s_texStippleSampler : register(s1);
float4 u_stipple;

vec2 blinn(vec3 _lightDir, vec3 _normal, vec3 _viewDir)
{
	float ndotl = dot(_normal, _lightDir);
	vec3 reflected = _lightDir - 2.0*ndotl*_normal; // reflect(_lightDir, _normal);
	float rdotv = dot(reflected, _viewDir);
	return vec2(ndotl, rdotv);
}

struct V2F
{
	vec3 v_normal    : NORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
	vec3 v_pos       : TEXCOORD1;
	vec3 v_view      : TEXCOORD2;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec2 viewport = (u_viewRect.zw - u_viewRect.xy) * vec2(1.0/8.0, 1.0/4.0);
	vec2 stippleUV = viewport*(input.v_pos.xy*0.5 + 0.5);
	vec4 color = texture2D(s_texColor, s_texColorSampler, input.v_texcoord0);
	if ( (u_stipple.x - texture2D(s_texStipple, s_texStippleSampler, stippleUV).x)*u_stipple.y > u_stipple.z
	||   color.w < 0.5)
	{
		discard;
	}

	vec3 lightDir = vec3(0.0, 0.0, -1.0);
	vec3 normal = normalize(input.v_normal);
	vec3 view = normalize(input.v_view);
	vec2 bln = blinn(lightDir, normal, view);
	float l = saturate(bln.y) + 0.12;

	color.xyz = toLinear(color.xyz)*l;
	return toGamma(color);
}
