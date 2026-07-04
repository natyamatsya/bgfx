// 1-to-1 Slang port of examples/09-hdr fs_hdr_mesh.sc.
// encodeRGBE8 comes from examples/common/shaderlib.sh (import shaderlib).
// blinn/fresnel/lit are defined inline in the stock .sc body, so they stay inline here.
// u_time is u_tonemap.w (see examples/09-hdr/common.sh).
import bgfx_shader;
import shaderlib;

TextureCube  s_texCube        : register(t0);
SamplerState s_texCubeSampler : register(s0);

vec4 u_tonemap;

vec2 blinn(vec3 _lightDir, vec3 _normal, vec3 _viewDir)
{
	float ndotl = dot(_normal, _lightDir);
	vec3 reflected = _lightDir - 2.0*ndotl*_normal; // reflect(_lightDir, _normal);
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

struct V2F
{
	vec3 v_pos    : TEXCOORD5;
	vec3 v_view   : TEXCOORD6;
	vec3 v_normal : NORMAL;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 lightDir = vec3(0.0, 0.0, -1.0);
	vec3 normal = normalize(input.v_normal);
	vec3 view = normalize(input.v_view);
	vec2 bln = blinn(lightDir, normal, view);
	vec4 lc = lit(bln.x, bln.y, 1.0);
	float fres = fresnel(bln.x, 0.2, 5.0);

	float index = ( (sin(input.v_pos.x*3.0+u_tonemap.w)*0.3+0.7)
				+ (  cos(input.v_pos.y*3.0+u_tonemap.w)*0.4+0.6)
				+ (  cos(input.v_pos.z*3.0+u_tonemap.w)*0.2+0.8)
				)*M_PI;

	vec3 color = vec3(sin(index*8.0)*0.4 + 0.6
					, sin(index*4.0)*0.4 + 0.6
					, sin(index*2.0)*0.4 + 0.6
					);

	color *= textureCube(s_texCube, s_texCubeSampler, reflect(view, -normal) ).xyz;

	return encodeRGBE8(color.xyz*lc.y + fres*pow(lc.z, 128.0) );
}
