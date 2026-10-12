// Slang port of examples/53-sky2/cs_atmo_transmittance.sc.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
//
// Reference: Hillaire, Sebastien. "A Scalable and Production Ready Sky and Atmosphere
// Rendering Technique." https://sebh.github.io/publications/egsr2020.pdf
import bgfx_shader;
import bgfx_compute;
import atmosphere;

// The uniforms this shader's stock counterpart touches through the atmosphere.sh accessors:
// the medium (rayleigh/mie/ozone) and the planet radii. u_atmoGround is not among them, and
// glslang strips it from the stock envelope, so it is not declared here either.
vec4 u_atmoRayleigh;
vec4 u_atmoMie;
vec4 u_atmoOzone;
vec4 u_atmoPlanet;

[[vk::image_format("rgba16f")]]
RWTexture2D<vec4> s_transmittance_out : register(u0);

static const int LUT_WIDTH  = 256;
static const int LUT_HEIGHT = 64;
static const int STEPS      = 40;

struct CSInput
{
	uint3 gl_GlobalInvocationID : SV_DispatchThreadID;
};

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(CSInput input)
{
	ivec2 coord = ivec2(input.gl_GlobalInvocationID.xy);
	if (coord.x >= LUT_WIDTH || coord.y >= LUT_HEIGHT)
		return;

	vec2 uv = (vec2(coord) + vec2(0.5, 0.5)) / vec2(LUT_WIDTH, LUT_HEIGHT);

	float r, mu;
	atmosphere_transmittance_params(uv, u_atmoPlanet, r, mu);

	float t_max = atmosphere_dist_to_sphere(r, mu, u_atmoPlanet.y);
	float dt    = t_max / float(STEPS);

	vec3 optical_depth = vec3(0.0, 0.0, 0.0);
	for (int i = 0; i < STEPS; i++)
	{
		float t = (float(i) + 0.5) * dt;
		float h = sqrt(r * r + t * t + 2.0 * r * mu * t) - u_atmoPlanet.x;

		vec3  scatter_r;
		float scatter_m;
		vec3  extinction;
		atmosphere_medium(max(h, 0.0), u_atmoRayleigh, u_atmoMie, u_atmoOzone, u_atmoPlanet, scatter_r, scatter_m, extinction);

		optical_depth += extinction * dt;
	}

	imageStore(s_transmittance_out, coord, vec4(exp(-optical_depth), 1.0));
}
