// 1-to-1 Slang port of examples/04-mesh fs_mesh.sc. blinn/fresnel/lit are defined
// inline in the stock .sc body, so they stay inline here (modularity rule).
import bgfx_shader;

vec4 u_time;

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
	vec3 v_pos    : TEXCOORD1;
	vec3 v_view   : TEXCOORD2;
	vec3 v_normal : NORMAL;
	vec4 v_color0 : COLOR0;
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

	float index = ( (sin(input.v_pos.x*3.0+u_time.x)*0.3+0.7)
				+ (  cos(input.v_pos.y*3.0+u_time.x)*0.4+0.6)
				+ (  cos(input.v_pos.z*3.0+u_time.x)*0.2+0.8)
				)*M_PI;

	vec3 color = vec3(sin(index*8.0)*0.4 + 0.6
					, sin(index*4.0)*0.4 + 0.6
					, sin(index*2.0)*0.4 + 0.6
					) * input.v_color0.xyz;

	vec4 fragColor;
	fragColor.xyz = pow(vec3(0.07, 0.06, 0.08) + color*lc.y + fres*pow(lc.z, 128.0), vec3_splat(1.0/2.2) );
	fragColor.w = 1.0;
	return fragColor;
}
