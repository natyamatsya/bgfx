// Slang port of examples/53-sky2/cs_atmo_skyview.sc -- the sky view LUT.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
//
// Reference: Hillaire, Sebastien. "A Scalable and Production Ready Sky and Atmosphere
// Rendering Technique." https://sebh.github.io/publications/egsr2020.pdf
import bgfx_shader;
import bgfx_compute;
import atmosphere;

Texture2D    s_atmo_transmittance        : register(t0);
SamplerState s_atmo_transmittanceSampler : register(s0);
Texture2D    s_atmo_multiscatter         : register(t2);
SamplerState s_atmo_multiscatterSampler  : register(s2);

[[vk::image_format("rgba16f")]]
RWTexture2D<vec4> s_skyview_out : register(u1);

// This pass touches every atmosphere.sh accessor, u_atmoGround included (the ground bounce).
vec4 u_atmoRayleigh;
vec4 u_atmoMie;
vec4 u_atmoOzone;
vec4 u_atmoPlanet;
vec4 u_atmoGround;

vec4 u_atmo_params;
vec4 u_atmo_params2; // x: sun cos zenith, y: view radius (km), zw: lut size

static const int STEPS = 16;

vec3 sample_transmittance_lut(float r, float mu)
{
	return texture2DLod(s_atmo_transmittance, s_atmo_transmittanceSampler, atmosphere_transmittance_uv(r, mu, u_atmoPlanet), 0.0).rgb;
}

vec3 sample_multiscatter_lut(float r, float mu_sun)
{
	vec2 uv = vec2(mu_sun * 0.5 + 0.5, (r - u_atmoPlanet.x) / (u_atmoPlanet.y - u_atmoPlanet.x) );
	return texture2DLod(s_atmo_multiscatter, s_atmo_multiscatterSampler, uv, 0.0).rgb;
}

struct CSInput
{
	uint3 gl_GlobalInvocationID : SV_DispatchThreadID;
};

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(CSInput input)
{
	ivec2 coord    = ivec2(input.gl_GlobalInvocationID.xy);
	ivec2 lut_size = ivec2(u_atmo_params2.zw);
	if (coord.x >= lut_size.x || coord.y >= lut_size.y)
		return;

	vec2 uv = (vec2(coord) + vec2(0.5, 0.5)) / vec2(lut_size);

	float r = u_atmo_params2.y;

	float view_zenith_cos, sun_rel_azimuth;
	atmosphere_skyview_params(uv, r, u_atmoPlanet, view_zenith_cos, sun_rel_azimuth);

	float sun_cos = u_atmo_params2.x;
	float sun_sin = sqrt(max(1.0 - sun_cos * sun_cos, 0.0) );

	vec3 sun_dir = vec3(sun_sin, 0.0, sun_cos);

	float view_sin = sqrt(max(1.0 - view_zenith_cos * view_zenith_cos, 0.0) );
	vec3  dir      = vec3(view_sin * cos(sun_rel_azimuth), view_sin * sin(sun_rel_azimuth), view_zenith_cos);

	bool  ground = atmosphere_hits_ground(r, dir.z, u_atmoPlanet);
	float t_max;
	if (ground)
		t_max = max(0.0, -r * dir.z - sqrt(max(r * r * (dir.z * dir.z - 1.0) + u_atmoPlanet.x * u_atmoPlanet.x, 0.0) ) );
	else
		t_max = atmosphere_dist_to_sphere(r, dir.z, u_atmoPlanet.y);

	float dt = t_max / float(STEPS);

	float cos_sun = dot(dir, sun_dir);
	float phase_r = atmosphere_phase_rayleigh(cos_sun);
	float phase_m = atmosphere_phase_mie(cos_sun, u_atmoMie);

	vec3 throughput = vec3(1.0, 1.0, 1.0);
	vec3 luminance  = vec3(0.0, 0.0, 0.0);

	for (int s = 0; s < STEPS; s++)
	{
		float t = (float(s) + 0.5) * dt;

		vec3  pos      = vec3(0.0, 0.0, r) + dir * t;
		float sample_r = length(pos);
		float h        = sample_r - u_atmoPlanet.x;
		float mu_sun   = dot(pos, sun_dir) / sample_r;

		vec3  scatter_r;
		float scatter_m;
		vec3  extinction;
		atmosphere_medium(max(h, 0.0), u_atmoRayleigh, u_atmoMie, u_atmoOzone, u_atmoPlanet, scatter_r, scatter_m, extinction);

		vec3 sun_t   = sample_transmittance_lut(sample_r, mu_sun);
		bool shadow  = atmosphere_hits_ground(sample_r, mu_sun, u_atmoPlanet);
		vec3 psi_ms  = sample_multiscatter_lut(sample_r, mu_sun);

		vec3 S = (scatter_r * phase_r + vec3_splat(scatter_m * phase_m) ) * sun_t * (shadow ? 0.0 : 1.0)
		       + (scatter_r + vec3_splat(scatter_m) ) * psi_ms * u_atmoOzone.w;

		vec3 step_transmittance = exp(-extinction * dt);
		vec3 safe_extinction    = max(extinction, vec3_splat(1e-7) );

		luminance  += throughput * (S - S * step_transmittance) / safe_extinction;
		throughput *= step_transmittance;
	}

	if (ground)
	{
		vec3  pos_ground = vec3(0.0, 0.0, r) + dir * t_max;
		float mu_ground  = clamp(dot(pos_ground, sun_dir) / u_atmoPlanet.x, -1.0, 1.0);
		vec3  sun_t      = sample_transmittance_lut(u_atmoPlanet.x, mu_ground);
		luminance += throughput * sun_t * max(mu_ground, 0.0) * u_atmoGround.xyz / ATMO_PI;
	}

	imageStore(s_skyview_out, coord, vec4(luminance * u_atmo_params.rgb, 1.0) );
}
