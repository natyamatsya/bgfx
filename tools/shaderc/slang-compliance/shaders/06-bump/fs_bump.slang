// 1-to-1 Slang port of examples/06-bump fs_bump.sc.
import bgfx_shader;

Texture2D    s_texColor         : register(t0);
SamplerState s_texColorSampler  : register(s0);
Texture2D    s_texNormal        : register(t1);
SamplerState s_texNormalSampler : register(s1);

vec4 u_lightPosRadius[4];
vec4 u_lightRgbInnerR[4];

vec2 blinn(vec3 _lightDir, vec3 _normal, vec3 _viewDir)
{
	float ndotl = dot(_normal, _lightDir);
	vec3 reflected = 2.0*ndotl*_normal - _lightDir;
	float rdotv = dot(reflected, _viewDir);
	return vec2(ndotl, rdotv);
}

float fresnel(float _ndotl, float _bias, float _pow)
{
	float facing = (1.0 - _ndotl);
	return max(_bias + (1.0 - _bias) * pow(facing, _pow), 0.0);
}

vec4 lit(float _ndotl, float _rdotv, float _m)
{
	float diff = max(0.0, _ndotl);
	float spec = step(0.0, _ndotl) * max(0.0, _rdotv * _m);
	return vec4(1.0, diff, spec, 1.0);
}

vec3 calcLight(int _idx, mat3 _tbn, vec3 _wpos, vec3 _normal, vec3 _view)
{
	vec3 lp = u_lightPosRadius[_idx].xyz - _wpos;
	float attn = 1.0 - smoothstep(u_lightRgbInnerR[_idx].w, 1.0, length(lp) / u_lightPosRadius[_idx].w);
	vec3 lightDir = mul( normalize(lp), _tbn );
	vec2 bln = blinn(lightDir, _normal, _view);
	vec4 lc = lit(bln.x, bln.y, 1.0);
	vec3 rgb = u_lightRgbInnerR[_idx].xyz * saturate(lc.y) * attn;
	return rgb;
}

struct V2F
{
	vec3 v_wpos      : TEXCOORD1;
	vec3 v_view      : TEXCOORD2;
	vec3 v_normal    : NORMAL;
	vec3 v_tangent   : TANGENT;
	vec3 v_bitangent : BINORMAL;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	mat3 tbn = mtxFromCols(input.v_tangent, input.v_bitangent, input.v_normal);
	vec3 normal;
	normal.xy = texture2D(s_texNormal, s_texNormalSampler, input.v_texcoord0).xy * 2.0 - 1.0;
	normal.z = sqrt(1.0 - dot(normal.xy, normal.xy) );
	vec3 view = normalize(input.v_view);
	vec3 lightColor;
	lightColor =  calcLight(0, tbn, input.v_wpos, normal, view);
	lightColor += calcLight(1, tbn, input.v_wpos, normal, view);
	lightColor += calcLight(2, tbn, input.v_wpos, normal, view);
	lightColor += calcLight(3, tbn, input.v_wpos, normal, view);
	vec4 color = toLinear(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0) );
	vec4 fragColor;
	fragColor.xyz = max(vec3_splat(0.05), lightColor.xyz)*color.xyz;
	fragColor.w = 1.0;
	return toGamma(fragColor);
}
