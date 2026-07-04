// 1-to-1 Slang port of examples/18-ibl fs_ibl_mesh.sc.
// calcFresnel/calcLambert/calcBlinn/specPwr are defined inline in the stock .sc body,
// so they stay inline here. toLinear/toFilmic/fixCubeLookup come from the central
// libraries (import bgfx_shader / shaderlib); mix comes from bgfx_shader_glsl_compat.
// u_params is the custom uniform array from examples/18-ibl/uniforms.sh; this stage
// reads up to [11], so the full [12] is declared.
import bgfx_shader;
import shaderlib;
import bgfx_shader_glsl_compat;

TextureCube  s_texCube           : register(t0);
SamplerState s_texCubeSampler    : register(s0);
TextureCube  s_texCubeIrr        : register(t1);
SamplerState s_texCubeIrrSampler : register(s1);

float4 u_params[12];
// uniforms.sh aliases:
//   u_mtx0..u_mtx3   = u_params[0..3]
//   u_glossiness     = u_params[4].x   u_reflectivity  = u_params[4].y
//   u_exposure       = u_params[4].z   u_bgType        = u_params[4].w
//   u_metalOrSpec    = u_params[5].x
//   u_doDiffuse      = u_params[6].x   u_doSpecular    = u_params[6].y
//   u_doDiffuseIbl   = u_params[6].z   u_doSpecularIbl = u_params[6].w
//   u_rgbDiff        = u_params[8]     u_rgbSpec       = u_params[9]
//   u_lightDir       = u_params[10].xyz u_lightCol     = u_params[11].xyz

vec3 calcFresnel(vec3 _cspec, float _dot, float _strength)
{
	return _cspec + (1.0 - _cspec)*pow(1.0 - _dot, 5.0) * _strength;
}

vec3 calcLambert(vec3 _cdiff, float _ndotl)
{
	return _cdiff*_ndotl;
}

vec3 calcBlinn(vec3 _cspec, float _ndoth, float _ndotl, float _specPwr)
{
	float norm = (_specPwr+8.0)*0.125;
	float brdf = pow(_ndoth, _specPwr)*_ndotl*norm;
	return _cspec*brdf;
}

float specPwr(float _gloss)
{
	return exp2(10.0*_gloss+2.0);
}

struct V2F
{
	vec3 v_normal : NORMAL;
	vec3 v_view   : TEXCOORD2;
};

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec4 gl_FragColor;

	// Light.
	vec3 ld     = normalize(u_params[10].xyz); // u_lightDir
	vec3 clight = u_params[11].xyz;            // u_lightCol

	// Input.
	vec3 nn = normalize(input.v_normal);
	vec3 vv = normalize(input.v_view);
	vec3 hh = normalize(vv + ld);

	float ndotv = clamp(dot(nn, vv), 0.0, 1.0);
	float ndotl = clamp(dot(nn, ld), 0.0, 1.0);
	float ndoth = clamp(dot(nn, hh), 0.0, 1.0);
	float hdotv = clamp(dot(hh, vv), 0.0, 1.0);

	// Material params.
	vec3  inAlbedo       = u_params[8].xyz; // u_rgbDiff.xyz
	float inReflectivity = u_params[4].y;   // u_reflectivity
	float inGloss        = u_params[4].x;   // u_glossiness

	// Reflection.
	vec3 refl;
	if (0.0 == u_params[5].x) // u_metalOrSpec // Metalness workflow.
	{
		refl = mix(vec3_splat(0.04), inAlbedo, inReflectivity);
	}
	else // Specular workflow.
	{
		refl = u_params[9].xyz * vec3_splat(inReflectivity); // u_rgbSpec.xyz
	}
	vec3 albedo = inAlbedo * (1.0 - inReflectivity);
	vec3 dirFresnel = calcFresnel(refl, hdotv, inGloss);
	vec3 envFresnel = calcFresnel(refl, ndotv, inGloss);

	vec3 lambert = u_params[6].x * calcLambert(albedo * (1.0 - dirFresnel), ndotl); // u_doDiffuse
	vec3 blinn   = u_params[6].y * calcBlinn(dirFresnel, ndoth, ndotl, specPwr(inGloss)); // u_doSpecular
	vec3 direct  = (lambert + blinn)*clight;

	// Note: Environment textures are filtered with cmft: https://github.com/dariomanesku/cmft
	float mip = 1.0 + 5.0*(1.0 - inGloss); // Use mip levels [1..6] for radiance.

	mat4 mtx = mtxFromCols(u_params[0], u_params[1], u_params[2], u_params[3]);
	vec3 vr = 2.0*ndotv*nn - vv; // Same as: -reflect(vv, nn);
	vec3 cubeR = normalize(mul(mtx, vec4(vr, 0.0)).xyz);
	vec3 cubeN = normalize(mul(mtx, vec4(nn, 0.0)).xyz);
	cubeR = fixCubeLookup(cubeR, mip, 256.0);

	vec3 radiance    = toLinear(textureCubeLod(s_texCube, s_texCubeSampler, cubeR, mip).xyz);
	vec3 irradiance  = toLinear(textureCube(s_texCubeIrr, s_texCubeIrrSampler, cubeN).xyz);
	vec3 envDiffuse  = albedo     * irradiance * u_params[6].z; // u_doDiffuseIbl
	vec3 envSpecular = envFresnel * radiance   * u_params[6].w; // u_doSpecularIbl
	vec3 indirect    = envDiffuse + envSpecular;

	// Color.
	vec3 color = direct + indirect;
	color = color * exp2(u_params[4].z); // u_exposure
	gl_FragColor.xyz = toFilmic(color);
	gl_FragColor.w = 1.0;
	return gl_FragColor;
}
