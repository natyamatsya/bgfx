// Cornell Box, ray traced in a compute shader (Slang).
//
// This is the *compute fallback* path: a self-contained analytic ray tracer that runs
// anywhere compute is supported, with no hardware ray tracing. The RT-accelerated path
// (ray query against a BVH) renders the same scene when BGFX_CAPS_RAY_TRACING is present.
//
// The scene is the classic Cornell Box: white floor/ceiling/back, a red left wall, a
// green right wall, an area light on the ceiling, and two boxes. Shading is direct
// lighting from the light's center plus a hard shadow ray and a small ambient term --
// enough to be unmistakably a Cornell Box; path-traced global illumination (the colour
// bleeding) is the natural next step.
import bgfx_shader;
import bgfx_compute;

RWTexture2D<float4> s_target : register(u0);

static const float kInf = 1e30;
static const float kEps = 1e-3;

struct Hit
{
	float  t;
	float3 n;
	float3 albedo;
	float3 emission;
};

// Ray vs an axis-aligned rectangle on plane { axis == value }, facing normal _n.
void hitQuad(float3 ro, float3 rd, int axis, float value, float3 lo, float3 hi, float3 n, float3 albedo, float3 emission, inout Hit best)
{
	float denom = rd[axis];
	if (abs(denom) < 1e-6) return;
	float t = (value - ro[axis]) / denom;
	if (t < kEps || t >= best.t) return;
	float3 p = ro + t*rd;
	// Bounds-check only the two in-plane axes. The plane axis equals `value` only to float
	// precision, so testing it too would reject ~half the hits (p[axis] just under value)
	// and speckle the surface.
	bool inBounds;
	if      (axis == 0) inBounds = p.y >= lo.y && p.y <= hi.y && p.z >= lo.z && p.z <= hi.z;
	else if (axis == 1) inBounds = p.x >= lo.x && p.x <= hi.x && p.z >= lo.z && p.z <= hi.z;
	else                inBounds = p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y;
	if (!inBounds) return;
	best.t = t; best.n = n; best.albedo = albedo; best.emission = emission;
}

// Ray vs axis-aligned box [lo,hi], albedo _albedo.
void hitBox(float3 ro, float3 rd, float3 lo, float3 hi, float3 albedo, inout Hit best)
{
	float3 inv = 1.0 / rd;
	float3 t0 = (lo - ro) * inv;
	float3 t1 = (hi - ro) * inv;
	float3 tsmall = min(t0, t1);
	float3 tbig   = max(t0, t1);
	float tNear = max(max(tsmall.x, tsmall.y), tsmall.z);
	float tFar  = min(min(tbig.x,  tbig.y),  tbig.z);
	if (tNear > tFar || tFar < kEps) return;
	float t = tNear > kEps ? tNear : tFar;
	if (t >= best.t) return;
	// Face normal: the slab that produced tNear.
	float3 n = float3(0, 0, 0);
	if      (tsmall.x == tNear) n = float3(rd.x > 0 ? -1 : 1, 0, 0);
	else if (tsmall.y == tNear) n = float3(0, rd.y > 0 ? -1 : 1, 0);
	else                        n = float3(0, 0, rd.z > 0 ? -1 : 1);
	best.t = t; best.n = n; best.albedo = albedo; best.emission = float3(0, 0, 0);
}

static const float3 kWhite = float3(0.73, 0.73, 0.73);
static const float3 kRed   = float3(0.65, 0.05, 0.05);
static const float3 kGreen = float3(0.12, 0.45, 0.15);
static const float3 kLightEmission = float3(18.0, 18.0, 18.0);

// Light rectangle on the ceiling.
static const float3 kLightLo = float3(-0.35, 0.997, -0.35);
static const float3 kLightHi = float3( 0.35, 0.999,  0.35);
static const float3 kLightCenter = float3(0.0, 0.997, 0.0);

Hit sceneHit(float3 ro, float3 rd)
{
	Hit best; best.t = kInf; best.n = float3(0,0,0); best.albedo = float3(0,0,0); best.emission = float3(0,0,0);

	// Walls (interior of a [-1,1]^3 box, open front at z=-1).
	hitQuad(ro, rd, 1, -1.0, float3(-1,-1,-1), float3(1,-1,1), float3(0, 1, 0), kWhite, float3(0,0,0), best); // floor
	hitQuad(ro, rd, 1,  1.0, float3(-1, 1,-1), float3(1, 1,1), float3(0,-1, 0), kWhite, float3(0,0,0), best); // ceiling
	hitQuad(ro, rd, 2,  1.0, float3(-1,-1, 1), float3(1, 1,1), float3(0, 0,-1), kWhite, float3(0,0,0), best); // back
	hitQuad(ro, rd, 0, -1.0, float3(-1,-1,-1), float3(-1,1,1), float3(1, 0, 0), kRed,   float3(0,0,0), best); // left
	hitQuad(ro, rd, 0,  1.0, float3( 1,-1,-1), float3(1, 1,1), float3(-1,0, 0), kGreen, float3(0,0,0), best); // right

	// Area light (slightly below the ceiling).
	hitQuad(ro, rd, 1, 0.998, kLightLo, kLightHi, float3(0,-1,0), float3(0,0,0), kLightEmission, best);

	// Two boxes.
	hitBox(ro, rd, float3(-0.62, -1.0, -0.10), float3(-0.12, 0.30, 0.40), kWhite, best); // tall
	hitBox(ro, rd, float3( 0.10, -1.0, -0.55), float3( 0.60, -0.40, -0.05), kWhite, best); // short

	return best;
}

static const float kShadowBias = 4e-3;

bool occluded(float3 ro, float3 rd, float maxT)
{
	// An occluder must be strictly between the surface and the light; the light itself
	// (emissive) and anything at/behind it does not shadow.
	Hit h = sceneHit(ro, rd);
	return h.t < maxT - kShadowBias && dot(h.emission, h.emission) <= 0.0;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
	// Resolution comes from the output image itself -- no uniform needed.
	float2 res = float2(imageSize(s_target) );
	if (float(dtid.x) >= res.x || float(dtid.y) >= res.y) return;

	// Primary ray. Image Y is top-down, so flip to a Y-up camera.
	float2 uv = (float2(dtid.xy) + 0.5) / res * 2.0 - 1.0;
	uv.y = -uv.y;
	float aspect = res.x / res.y;

	float3 eye = float3(0.0, 0.0, -3.8);
	float tanHalfFov = tan(radians(40.0) * 0.5);
	float3 rd = normalize(float3(uv.x * tanHalfFov * aspect, uv.y * tanHalfFov, 1.0));

	Hit h = sceneHit(eye, rd);

	float3 color = float3(0.02, 0.02, 0.02); // background
	if (h.t < kInf)
	{
		if (dot(h.emission, h.emission) > 0.0)
		{
			color = h.emission;
		}
		else
		{
			float3 p = eye + h.t*rd;
			float3 toLight = kLightCenter - p;
			float dist = length(toLight);
			float3 wi = toLight / dist;

			float ndotl = max(0.0, dot(h.n, wi) );
			float3 ambient = h.albedo * 0.12;
			float3 direct  = float3(0, 0, 0);
			if (ndotl > 0.0 && !occluded(p + h.n*kShadowBias, wi, dist) )
			{
				direct = h.albedo * kLightEmission * (ndotl / (dist*dist) ) * 0.15;
			}
			color = ambient + direct;
		}
	}

	// Reinhard tonemap + gamma.
	color = color / (color + 1.0);
	color = pow(color, float3(1.0/2.2, 1.0/2.2, 1.0/2.2) );

	imageStore(s_target, ivec2(dtid.xy), float4(color, 1.0) );
}
