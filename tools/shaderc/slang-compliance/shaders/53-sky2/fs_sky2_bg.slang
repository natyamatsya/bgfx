// Slang port of examples/53-sky2/fs_sky2_bg.sc -- the sky background pass.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
//
// Reference: Hillaire, Sebastien. "A Scalable and Production Ready Sky and Atmosphere
// Rendering Technique." https://sebh.github.io/publications/egsr2020.pdf
import bgfx_shader;
import atmosphere;
import sky2_common;

Texture2D    s_sky_view                  : register(t0);
SamplerState s_sky_viewSampler           : register(s0);
Texture2D    s_atmo_transmittance        : register(t1);
SamplerState s_atmo_transmittanceSampler : register(s1);

// Of the atmosphere.sh uniforms this pass reaches only the planet radii (skyview_uv,
// hits_ground, transmittance_uv); glslang strips the rest from the stock envelope.
vec4 u_atmoPlanet;

mat4 u_skyInvViewProj;
vec4 u_skyParams;    // x: view radius (km), y: cos sun angular radius, z: sun disc scale
vec4 u_sunDirection;
vec4 u_sunRadiance;

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD2;
};

// sun relative azimuth of dir
float sun_relative_azimuth(vec3 dir, vec3 to_sun)
{
	vec2 d = vec2(dir.x, dir.z);
	vec2 s = vec2(to_sun.x, to_sun.z);

	float dl = length(d);
	float sl = length(s);
	if (dl < 1e-5 || sl < 1e-5)
		return 0.0;

	d /= dl;
	s /= sl;

	return atan2(d.x * s.y - d.y * s.x, dot(d, s) );
}

[shader("fragment")]
vec4 fragmentMain(V2F input) : SV_Target
{
	// reconstruct the world space view ray
	vec4 nearp = mul(u_skyInvViewProj, vec4(input.v_texcoord0.xy, 0.0, 1.0) );
	vec4 farp  = mul(u_skyInvViewProj, vec4(input.v_texcoord0.xy, 1.0, 1.0) );
	vec3 eye   = nearp.xyz / nearp.w;
	vec3 at    = farp.xyz  / farp.w;
	vec3 dir   = normalize(at - eye);

	float r      = u_skyParams.x;
	vec3  to_sun = -normalize(u_sunDirection.xyz);

	vec2 uv = atmosphere_skyview_uv(r, dir.y, sun_relative_azimuth(dir, to_sun), u_atmoPlanet);
	vec3 radiance = texture2DLod(s_sky_view, s_sky_viewSampler, uv, 0.0).rgb;

	// Sun disc, circumsolar halo
	float cos_view_sun = dot(dir, to_sun);
	if (!atmosphere_hits_ground(r, dir.y, u_atmoPlanet) )
	{
		vec3 transmittance = texture2DLod(s_atmo_transmittance, s_atmo_transmittanceSampler, atmosphere_transmittance_uv(r, dir.y, u_atmoPlanet), 0.0).rgb;

		float halo = exp2(-(1.0 - cos_view_sun) * 12000.0);
		radiance += u_sunRadiance.rgb * transmittance * (u_skyParams.z * 0.03) * halo;

		if (cos_view_sun >= u_skyParams.y)
		{
			float x2   = saturate((1.0 - cos_view_sun) / max(1.0 - u_skyParams.y, 1e-7) );
			float limb = pow(max(1.0 - x2, 0.0), 0.3);
			radiance += u_sunRadiance.rgb * u_skyParams.z * transmittance * limb;
		}
	}

	return vec4(sky2_tonemap(radiance), 1.0);
}
