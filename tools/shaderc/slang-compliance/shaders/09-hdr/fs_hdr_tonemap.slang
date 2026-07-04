// 1-to-1 Slang port of examples/09-hdr fs_hdr_tonemap.sc.
// decodeRGBE8/decodeRE8/convertRGB2Yxy/convertYxy2RGB come from examples/common/shaderlib.sh
// (import shaderlib); reinhard2/blur9 come from examples/09-hdr/common.sh (import common).
import bgfx_shader;
import shaderlib;
import common;

Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);
Texture2D    s_texLum          : register(t1);
SamplerState s_texLumSampler   : register(s1);
Texture2D    s_texBlur         : register(t2);
SamplerState s_texBlurSampler  : register(s2);

vec4 u_tonemap;

struct V2F
{
	vec2 v_texcoord0 : TEXCOORD0;
	vec4 v_texcoord1 : TEXCOORD1;
	vec4 v_texcoord2 : TEXCOORD2;
	vec4 v_texcoord3 : TEXCOORD3;
	vec4 v_texcoord4 : TEXCOORD4;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 rgb = decodeRGBE8(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0) );
	float lum = clamp(decodeRE8(texture2D(s_texLum, s_texLumSampler, input.v_texcoord0) ), 0.1, 0.7);

	vec3 Yxy = convertRGB2Yxy(rgb);

	float middleGray = u_tonemap.x;
	float whiteSqr   = u_tonemap.y;
	float threshold  = u_tonemap.z;
	float offset     = u_tonemap.w;

	float lp = Yxy.x * middleGray / (lum + 0.0001);
	Yxy.x = reinhard2(lp, whiteSqr);

	rgb = convertYxy2RGB(Yxy);

	vec4 blur = blur9(s_texBlur
					, s_texBlurSampler
					, input.v_texcoord0
					, input.v_texcoord1
					, input.v_texcoord2
					, input.v_texcoord3
					, input.v_texcoord4
					);

	rgb += 0.6 * blur.xyz;

	return toGamma(vec4(rgb, 1.0) );
}
