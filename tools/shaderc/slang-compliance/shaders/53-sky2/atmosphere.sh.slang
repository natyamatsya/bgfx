// Slang port of examples/53-sky2/atmosphere.sh -- the Hillaire sky model shared by the
// atmosphere LUT compute passes and the sky shaders. `import atmosphere;`.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
//
// Reference: Hillaire, Sebastien. "A Scalable and Production Ready Sky and Atmosphere
// Rendering Technique." https://sebh.github.io/publications/egsr2020.pdf
//
// The stock header declares the atmosphere uniforms and reaches them through #define
// accessors (ATMO_TOP_RADIUS and friends). Neither survives an `import`: a preprocessor
// macro does not cross module boundaries, and a uniform declared here would be reported by
// every importer, while glslang strips the ones a given shader does not reference -- so
// cs_atmo_transmittance, which never touches u_atmoGround, would over-report it. These are
// therefore pure functions that take what they need, and each importer declares exactly the
// uniforms its stock counterpart's macro expansion touches. Same shape as
// 21-deferred/common.sh.slang. The stock accessors map as:
//
//   ATMO_BOTTOM_RADIUS u_atmoPlanet.x    ATMO_RAYLEIGH_SCATTER u_atmoRayleigh.xyz
//   ATMO_TOP_RADIUS    u_atmoPlanet.y    ATMO_RAYLEIGH_H       u_atmoRayleigh.w
//   ATMO_OZONE_CENTER  u_atmoPlanet.z    ATMO_MIE_SCATTER      u_atmoMie.x
//   ATMO_OZONE_HALF    u_atmoPlanet.w    ATMO_MIE_EXTINCTION   u_atmoMie.y
//   ATMO_OZONE_ABSORB  u_atmoOzone.xyz   ATMO_MIE_H            u_atmoMie.z
//   ATMO_MS_STRENGTH   u_atmoOzone.w     ATMO_MIE_G            u_atmoMie.w
//   ATMO_GROUND_ALBEDO u_atmoGround.xyz
import bgfx_shader;

public static const float ATMO_PI = 3.14159265359;

public void atmosphere_medium(float h, vec4 rayleigh, vec4 mie, vec4 ozone, vec4 planet, out vec3 scatter_rayleigh, out float scatter_mie, out vec3 extinction)
{
	float density_r = exp(-h / rayleigh.w);
	float density_m = exp(-h / mie.z);
	float density_o = max(0.0, 1.0 - abs(h - planet.z) / planet.w);

	scatter_rayleigh = rayleigh.xyz * density_r;
	scatter_mie      = mie.x * density_m;

	extinction = rayleigh.xyz * density_r
			   + vec3_splat(mie.y * density_m)
			   + ozone.xyz * density_o;
}

public float atmosphere_phase_rayleigh(float cos_theta)
{
	return 3.0 / (16.0 * ATMO_PI) * (1.0 + cos_theta * cos_theta);
}

public float atmosphere_phase_mie(float cos_theta, vec4 mie)
{
	float g  = mie.w;
	float g2 = g * g;
	float d  = 1.0 + g2 - 2.0 * g * cos_theta;
	return 3.0 / (8.0 * ATMO_PI) * ((1.0 - g2) * (1.0 + cos_theta * cos_theta)) / ((2.0 + g2) * d * sqrt(max(d, 1e-6)));
}

public float atmosphere_dist_to_sphere(float r, float mu, float R)
{
	float disc = r * r * (mu * mu - 1.0) + R * R;
	return max(0.0, -r * mu + sqrt(max(disc, 0.0)));
}

public bool atmosphere_hits_ground(float r, float mu, vec4 planet)
{
	return mu < 0.0 && (r * r * (mu * mu - 1.0) + planet.x * planet.x) >= 0.0;
}

// transmittance lut parameterization Bruneton's distance based mapping.
public vec2 atmosphere_transmittance_uv(float r, float mu, vec4 planet)
{
	float H   = sqrt(planet.y * planet.y - planet.x * planet.x);
	float rho = sqrt(max(r * r - planet.x * planet.x, 0.0));

	float d     = atmosphere_dist_to_sphere(r, mu, planet.y);
	float d_min = planet.y - r;
	float d_max = rho + H;

	return vec2((d - d_min) / (d_max - d_min), rho / H);
}

public void atmosphere_transmittance_params(vec2 uv, vec4 planet, out float r, out float mu)
{
	float H   = sqrt(planet.y * planet.y - planet.x * planet.x);
	float rho = uv.y * H;

	r = sqrt(rho * rho + planet.x * planet.x);

	float d_min = planet.y - r;
	float d_max = rho + H;
	float d     = d_min + uv.x * (d_max - d_min);

	mu = (d <= 0.0) ? 1.0 : clamp((H * H - rho * rho - d * d) / (2.0 * r * d), -1.0, 1.0);
}

// sky view ly parameterization.
public vec2 atmosphere_skyview_uv(float r, float view_zenith_cos, float sun_rel_azimuth, vec4 planet)
{
	float v_horizon      = sqrt(max(r * r - planet.x * planet.x, 0.0));
	float beta           = acos(clamp(v_horizon / r, -1.0, 1.0));
	float zenith_horizon = ATMO_PI - beta;
	float view_zenith    = acos(clamp(view_zenith_cos, -1.0, 1.0));

	float v;
	if (view_zenith < zenith_horizon)
	{
		float coord = view_zenith / zenith_horizon;
		v = (1.0 - sqrt(1.0 - coord)) * 0.5;
	}
	else
	{
		float coord = (view_zenith - zenith_horizon) / max(beta, 1e-4);
		v = sqrt(saturate(coord)) * 0.5 + 0.5;
	}

	float u = sun_rel_azimuth / (2.0 * ATMO_PI) + 0.5;
	return vec2(u, v);
}

public void atmosphere_skyview_params(vec2 uv, float r, vec4 planet, out float view_zenith_cos, out float sun_rel_azimuth)
{
	float v_horizon      = sqrt(max(r * r - planet.x * planet.x, 0.0));
	float beta           = acos(clamp(v_horizon / r, -1.0, 1.0));
	float zenith_horizon = ATMO_PI - beta;

	float view_zenith;
	if (uv.y < 0.5)
	{
		float coord = 1.0 - uv.y * 2.0;
		view_zenith = zenith_horizon * (1.0 - coord * coord);
	}
	else
	{
		float coord = uv.y * 2.0 - 1.0;
		view_zenith = zenith_horizon + beta * coord * coord;
	}

	view_zenith_cos = cos(view_zenith);
	sun_rel_azimuth = (uv.x - 0.5) * 2.0 * ATMO_PI;
}
