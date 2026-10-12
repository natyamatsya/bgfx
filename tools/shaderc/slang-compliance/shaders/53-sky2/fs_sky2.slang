// Slang port of examples/53-sky2/fs_sky2.sc -- the terrain pass: triplanar hextiled
// albedo, PCF sun shadow, and an aerial-perspective march to the fragment.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
//
// Reference: Hillaire, Sebastien. "A Scalable and Production Ready Sky and Atmosphere
// Rendering Technique." https://sebh.github.io/publications/egsr2020.pdf
import bgfx_shader;
import bgfx_shader_glsl_compat; // mix, dFdx, dFdy
import atmosphere;
import sky2_common;
import hextile;

static const float TERRAIN_TILE        = 0.5; // in km
static const float TERRAIN_ROCK_SLOPE  = 0.1;
static const float TERRAIN_DETILE_ROT  = 0.5;

static const float TERRAIN_SHADOW_BIAS = 0.0015;

Texture2D    s_atmo_transmittance        : register(t0);
SamplerState s_atmo_transmittanceSampler : register(s0);
Texture2D    s_atmo_multiscatter         : register(t1);
SamplerState s_atmo_multiscatterSampler  : register(s1);
Texture2D    s_sky_view                  : register(t2);
SamplerState s_sky_viewSampler           : register(s2);
Texture2D    s_grass                     : register(t3);
SamplerState s_grassSampler              : register(s3);
Texture2D    s_rock                      : register(t4);
SamplerState s_rockSampler               : register(s4);
Texture2D    s_shadowMap                 : register(t5);
SamplerState s_shadowMapSampler          : register(s5);

// The atmosphere.sh accessors this pass reaches: the medium and the planet radii. The
// ground albedo is not among them, so glslang strips u_atmoGround from the stock envelope.
vec4 u_atmoRayleigh;
vec4 u_atmoMie;
vec4 u_atmoOzone;
vec4 u_atmoPlanet;

vec4 u_sunDirection;
vec4 u_sunRadiance;
vec4 u_cameraPos;     // (km)
vec4 u_skyParams;     // x: view radius (km)
vec4 u_aerialParams;  // x: in-scatter, y: density, z: ambient
vec4 u_shadowParams;  // x: uv texel, y: world texel (km), z: enabled
mat4 u_lightMtx;

static const int AERIAL_STEPS = 16;

struct V2F
{
	vec4 pos      : SV_Position;
	vec3 v_normal : TEXCOORD0;
	vec3 v_wpos   : TEXCOORD1;
};

vec3 tr_lut(float r, float mu)
{
	return texture2DLod(s_atmo_transmittance, s_atmo_transmittanceSampler, atmosphere_transmittance_uv(r, mu, u_atmoPlanet), 0.0).rgb;
}

vec3 ms_lut(float r, float mu_sun)
{
	vec2 uv = vec2(mu_sun * 0.5 + 0.5, (r - u_atmoPlanet.x) / (u_atmoPlanet.y - u_atmoPlanet.x) );
	return texture2DLod(s_atmo_multiscatter, s_atmo_multiscatterSampler, uv, 0.0).rgb;
}

void hexTerrainFetch(vec2 uv, float rotStrength, out vec3 grass, out vec3 rock)
{
	vec2 dSTdx = dFdx(uv);
	vec2 dSTdy = dFdy(uv);

	vec2 uv1, uv2, uv3;
	mat2 rot1, rot2, rot3;
	vec3 bary;
	hextile_setup(uv, rotStrength, uv1, uv2, uv3, rot1, rot2, rot3, bary);

	grass = hextile_blend(
		  texture2DGrad(s_grass, s_grassSampler, uv1, mul(dSTdx, rot1), mul(dSTdy, rot1) ).xyz
		, texture2DGrad(s_grass, s_grassSampler, uv2, mul(dSTdx, rot2), mul(dSTdy, rot2) ).xyz
		, texture2DGrad(s_grass, s_grassSampler, uv3, mul(dSTdx, rot3), mul(dSTdy, rot3) ).xyz
		, bary
		);

	rock = hextile_blend(
		  texture2DGrad(s_rock, s_rockSampler, uv1, mul(dSTdx, rot1), mul(dSTdy, rot1) ).xyz
		, texture2DGrad(s_rock, s_rockSampler, uv2, mul(dSTdx, rot2), mul(dSTdy, rot2) ).xyz
		, texture2DGrad(s_rock, s_rockSampler, uv3, mul(dSTdx, rot3), mul(dSTdy, rot3) ).xyz
		, bary
		);
}

// 3x3 PCF
float sun_shadow(vec3 wpos, vec3 N, float ndotl)
{
	if (u_shadowParams.z < 0.5)
		return 1.0;

	float nOffset = u_shadowParams.y * (2.0 + 6.0 * (1.0 - ndotl) );
	vec4  sc = mul(u_lightMtx, vec4(wpos + N * nOffset, 1.0) );
	vec3  c  = sc.xyz / sc.w;

	if (c.x < 0.0 || c.x > 1.0 || c.y < 0.0 || c.y > 1.0 || c.z > 1.0)
		return 1.0;

	float bias  = TERRAIN_SHADOW_BIAS * (1.0 + 3.0 * (1.0 - ndotl) );
	float texel = u_shadowParams.x;

	float sum = 0.0;
	for (int dy = -1; dy <= 1; dy++)
	{
		for (int dx = -1; dx <= 1; dx++)
		{
			float stored = texture2D(s_shadowMap, s_shadowMapSampler, c.xy + vec2(float(dx), float(dy) ) * texel).r;
			sum += (c.z - bias > stored) ? 0.0 : 1.0;
		}
	}

	return sum / 9.0;
}

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	vec3 N = normalize(input.v_normal);

	vec3 tw = abs(N);
	tw = tw * tw * tw;
	tw = tw / max(tw.x + tw.y + tw.z, 1e-4);

	vec3 pw = input.v_wpos * TERRAIN_TILE;

	vec3 grassX, rockX, grassY, rockY, grassZ, rockZ;
	hexTerrainFetch(pw.zy, TERRAIN_DETILE_ROT, grassX, rockX);
	hexTerrainFetch(pw.xz, TERRAIN_DETILE_ROT, grassY, rockY);
	hexTerrainFetch(pw.xy, TERRAIN_DETILE_ROT, grassZ, rockZ);

	vec3 grass = grassX * tw.x + grassY * tw.y + grassZ * tw.z;
	vec3 rock  = rockX  * tw.x + rockY  * tw.y + rockZ  * tw.z;

	// srgb -> linear
	grass = pow(grass, vec3_splat(2.2) );
	rock  = pow(rock,  vec3_splat(2.2) );

	float slope  = 1.0 - N.y;
	float rockW  = smoothstep(TERRAIN_ROCK_SLOPE, TERRAIN_ROCK_SLOPE + 0.2, slope);
	vec3  albedo = mix(grass, rock, rockW);

	vec3  to_sun = -normalize(u_sunDirection.xyz);
	float mu_sun = to_sun.y;

	float frag_alt = max(input.v_wpos.y, 0.0);
	float surf_r   = u_atmoPlanet.x + frag_alt;

	// direct sun Lambert BRDF
	vec3  sun_t  = tr_lut(surf_r, mu_sun);
	float ndotl  = max(dot(N, to_sun), 0.0);
	float shadow = sun_shadow(input.v_wpos, N, ndotl);
	vec3  direct = albedo * (1.0 / ATMO_PI) * u_sunRadiance.rgb * sun_t * ndotl * shadow;

	float lut_r = u_skyParams.x;
	vec3  sky_avg = texture2DLod(s_sky_view, s_sky_viewSampler, atmosphere_skyview_uv(lut_r, 1.00, 0.0, u_atmoPlanet), 0.0).rgb
	              + texture2DLod(s_sky_view, s_sky_viewSampler, atmosphere_skyview_uv(lut_r, 0.35, 0.0, u_atmoPlanet), 0.0).rgb
	              + texture2DLod(s_sky_view, s_sky_viewSampler, atmosphere_skyview_uv(lut_r, 0.35, ATMO_PI, u_atmoPlanet), 0.0).rgb;
	sky_avg *= 1.0 / 3.0;

	vec3 ambient = albedo * sky_avg * (0.4 + 0.6 * saturate(N.y) ) * u_aerialParams.z;

	vec3 lit = direct + ambient;

	// aerial perspective march camera -> fragment
	vec3  cam  = u_cameraPos.xyz;
	vec3  ray  = input.v_wpos - cam;
	float dist = length(ray);
	vec3  vdir = ray / max(dist, 1e-6);

	float cos_sun_view = dot(vdir, to_sun);
	float phase_r = atmosphere_phase_rayleigh(cos_sun_view);
	float phase_m = atmosphere_phase_mie(cos_sun_view, u_atmoMie);

	float density = u_aerialParams.y;
	float dt      = dist / float(AERIAL_STEPS);

	vec3 throughput = vec3(1.0, 1.0, 1.0);
	vec3 inscatter  = vec3(0.0, 0.0, 0.0);

	for (int i = 0; i < AERIAL_STEPS; i++)
	{
		float t   = (float(i) + 0.5) * dt;
		vec3  p   = cam + vdir * t;
		float alt = max(p.y, 0.0);
		float sr  = u_atmoPlanet.x + alt;

		vec3  scatter_r;
		float scatter_m;
		vec3  extinction;
		atmosphere_medium(alt, u_atmoRayleigh, u_atmoMie, u_atmoOzone, u_atmoPlanet, scatter_r, scatter_m, extinction);

		scatter_r  *= density;
		scatter_m  *= density;
		extinction *= density;

		vec3 st  = tr_lut(sr, mu_sun);
		vec3 psi = ms_lut(sr, mu_sun) * u_atmoOzone.w;

		vec3 S = (scatter_r * phase_r + vec3_splat(scatter_m * phase_m) ) * st
		       + (scatter_r + vec3_splat(scatter_m) ) * psi;
		S *= u_sunRadiance.rgb;

		vec3 step_t = exp(-extinction * dt);
		vec3 safe_e = max(extinction, vec3_splat(1e-7) );

		inscatter  += throughput * (S - S * step_t) / safe_e;
		throughput *= step_t;
	}

	vec3 color = lit * throughput + inscatter * u_aerialParams.x;

	return vec4(sky2_tonemap(color), 1.0);
}
