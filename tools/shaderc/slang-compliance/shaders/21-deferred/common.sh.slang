// Slang port of examples/21-deferred common.sh -- the example-local lighting helpers
// shared by the deferred light shaders. `import common;`.
//
// These are pure functions: blinn/fresnel/lit/powRgba/calcLight take everything as
// parameters and reference no uniforms/samplers, so nothing resource-shaped lives here
// and importers keep their own light uniforms (u_lightPosRadius, u_lightRgbInnerR,
// u_mtx, s_normal, s_depth) -- the reflection envelope is unchanged.
import bgfx_shader; // vec2/vec3/vec4 aliases, vec3_splat

public vec2 blinn(vec3 _lightDir, vec3 _normal, vec3 _viewDir)
{
	float ndotl = dot(_normal, _lightDir);
	vec3 reflected = _lightDir - 2.0*ndotl*_normal; // reflect(_lightDir, _normal);
	float rdotv = dot(reflected, _viewDir);
	return vec2(ndotl, rdotv);
}

public float fresnel(float _ndotl, float _bias, float _pow)
{
	float facing = (1.0 - _ndotl);
	return max(_bias + (1.0 - _bias) * pow(facing, _pow), 0.0);
}

public vec4 lit(float _ndotl, float _rdotv, float _m)
{
	float diff = max(0.0, _ndotl);
	float spec = step(0.0, _ndotl) * max(0.0, _rdotv * _m);
	return vec4(1.0, diff, spec, 1.0);
}

public vec4 powRgba(vec4 _rgba, float _pow)
{
	vec4 result;
	result.xyz = pow(_rgba.xyz, vec3_splat(_pow) );
	result.w = _rgba.w;
	return result;
}

public vec3 calcLight(vec3 _wpos, vec3 _normal, vec3 _view, vec3 _lightPos, float _lightRadius, vec3 _lightRgb, float _lightInner)
{
	vec3 lp = _lightPos - _wpos;
	float attn = 1.0 - smoothstep(_lightInner, 1.0, length(lp) / _lightRadius);
	vec3 lightDir = normalize(lp);
	vec2 bln = blinn(lightDir, _normal, _view);
	vec4 lc = lit(bln.x, bln.y, 1.0);
	vec3 rgb = _lightRgb * saturate(lc.y) * attn;
	return rgb;
}
