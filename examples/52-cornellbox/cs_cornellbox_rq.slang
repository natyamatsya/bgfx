// Cornell Box, path traced with hardware ray query (Slang).
//
// This is the *RT-accelerated* path, selected when BGFX_CAPS_RAY_TRACING is present. The
// geometry is three BLASes (walls+light, tall box, short box) instanced by a TLAS; the two
// box instances rotate via bgfx::updateTlas when the app's rotation mode is on. Shading is
// a progressive path tracer (next-event estimation toward the area light + cosine-weighted
// diffuse bounces) accumulated across frames in s_accum; the running average is tonemapped
// into s_target every frame. The analytic compute fallback (cs_cornellbox.slang) implements
// the same estimator without hardware RT.
import bgfx_shader;
import bgfx_compute;

// bgfx flattens the t/u register spaces into one bind namespace, so the register NUMBERS
// must be globally unique across resources. scene -> stage 0, s_accum -> stage 1,
// s_target -> stage 2, materials -> stage 3.
uniform RaytracingAccelerationStructure scene : register(t0);

RWTexture2D<float4> s_accum  : register(u1); // rgb = radiance sum, a = sample count
RWTexture2D<float4> s_target : register(u2); // tonemapped display image

struct Material
{
	float4 albedo;   // xyz
	float4 emission; // xyz
	float4 normal;   // xyz, inward-facing, in BLAS-local space
};
RWStructuredBuffer<Material> materials : register(u3);

// x = frame index (RNG seed), y = reset accumulation (>0.5), z = box rotation angle.
uniform float4 u_params;

static const float3 kLightLo = float3(-0.35, 0.997, -0.35);
static const float3 kLightHi = float3( 0.35, 0.997,  0.35);
static const float3 kLightEmission = float3(18.0, 18.0, 18.0);
static const float  kLightArea = 0.7 * 0.7;
static const float  kShadowBias = 4e-3;
static const float  kPi = 3.14159265;
static const int    kBounces = 4;
static const uint   kTrisPerInstance = 12;

// --- RNG (PCG) --------------------------------------------------------------------------

uint pcgHash(uint v)
{
	v = v*747796405u + 2891336453u;
	uint w = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
	return (w >> 22u) ^ w;
}

float rnd(inout uint state)
{
	state = pcgHash(state);
	return float(state) * (1.0 / 4294967296.0);
}

// Rotation about Y matching bx::mtxRotateY's (row-vector) convention.
float3 rotY(float3 v, float a)
{
	float c = cos(a), s = sin(a);
	return float3(c*v.x - s*v.z, v.y, s*v.x + c*v.z);
}

float3 cosineSample(float3 n, float u1, float u2)
{
	float ang = 2.0*kPi*u1;
	float r = sqrt(u2);
	float3 t = normalize(cross(abs(n.y) < 0.99 ? float3(0,1,0) : float3(1,0,0), n) );
	float3 b = cross(n, t);
	return normalize(t*(r*cos(ang)) + b*(r*sin(ang)) + n*sqrt(max(0.0, 1.0 - u2)) );
}

// --- tracing ----------------------------------------------------------------------------

// Closest hit: material index (instance*12 + primitive) or -1 on miss; t written back.
int traceClosest(float3 ro, float3 rd, float tmax, out float tHit)
{
	RayDesc rdesc;
	rdesc.Origin    = ro;
	rdesc.Direction = rd;
	rdesc.TMin      = 1e-3;
	rdesc.TMax      = tmax;

	RayQuery<RAY_FLAG_NONE> rq;
	rq.TraceRayInline(scene, RAY_FLAG_NONE, 0xff, rdesc);
	rq.Proceed();

	if (rq.CommittedStatus() == COMMITTED_TRIANGLE_HIT)
	{
		tHit = rq.CommittedRayT();
		return int(uint(rq.CommittedInstanceIndex())*kTrisPerInstance + rq.CommittedPrimitiveIndex());
	}
	tHit = tmax;
	return -1;
}

// World-space surface normal for a hit: BLAS-local stored normal, rotated for the two box
// instances (tall = +angle, short = -angle; matches the app's updateTlas transforms).
float3 hitNormal(int matIdx)
{
	float3 n = materials[matIdx].normal.xyz;
	uint inst = uint(matIdx) / kTrisPerInstance;
	if (inst == 1u) n = rotY(n,  u_params.z);
	if (inst == 2u) n = rotY(n, -u_params.z);
	return n;
}

bool occluded(float3 ro, float3 rd, float maxT)
{
	float t;
	int matIdx = traceClosest(ro, rd, maxT, t);
	if (matIdx < 0) return false;
	if (t >= maxT - kShadowBias) return false;
	float3 e = materials[matIdx].emission.xyz;
	return dot(e, e) <= 0.0; // the light itself does not shadow
}

float3 pathTrace(float3 ro, float3 rd, inout uint rng)
{
	float3 radiance   = float3(0, 0, 0);
	float3 throughput = float3(1, 1, 1);

	for (int bounce = 0; bounce < kBounces; ++bounce)
	{
		float t;
		int matIdx = traceClosest(ro, rd, 1e30, t);
		if (matIdx < 0)
		{
			if (bounce == 0) radiance = float3(0.02, 0.02, 0.02); // open front: background
			break;
		}

		Material m = materials[matIdx];
		float3 emission = m.emission.xyz;
		if (dot(emission, emission) > 0.0)
		{
			// Direct light hits only; indirect lighting is handled by NEE below.
			if (bounce == 0) radiance += throughput * emission;
			break;
		}

		float3 albedo = m.albedo.xyz;
		float3 n = hitNormal(matIdx);
		float3 p = ro + t*rd;

		// Next-event estimation: sample a point on the area light.
		float3 lp = float3(
			  lerp(kLightLo.x, kLightHi.x, rnd(rng))
			, kLightLo.y
			, lerp(kLightLo.z, kLightHi.z, rnd(rng))
			);
		float3 toL = lp - p;
		float d2 = dot(toL, toL);
		float dist = sqrt(d2);
		float3 wi = toL / dist;
		float ndotl = dot(n, wi);
		float lndotl = wi.y; // dot(lightNormal=(0,-1,0), -wi)
		if (ndotl > 0.0 && lndotl > 0.0 && !occluded(p + n*kShadowBias, wi, dist) )
		{
			radiance += throughput * (albedo / kPi) * kLightEmission * (ndotl * lndotl / d2) * kLightArea;
		}

		// Cosine-weighted diffuse bounce; BRDF/pdf leaves just the albedo.
		rd = cosineSample(n, rnd(rng), rnd(rng) );
		ro = p + n*kShadowBias;
		throughput *= albedo;
	}

	return radiance;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
	float2 res = float2(imageSize(s_target) );
	if (float(dtid.x) >= res.x || float(dtid.y) >= res.y) return;

	uint rng = pcgHash(dtid.y*9781u + dtid.x + pcgHash(uint(u_params.x)*2971u) );

	// Primary ray with sub-pixel jitter. Image Y is top-down, so flip to a Y-up camera.
	float2 jitter = float2(rnd(rng), rnd(rng) );
	float2 uv = (float2(dtid.xy) + jitter) / res * 2.0 - 1.0;
	uv.y = -uv.y;
	float aspect = res.x / res.y;

	float3 eye = float3(0.0, 0.0, -3.8);
	float tanHalfFov = tan(radians(40.0) * 0.5);
	float3 rd = normalize(float3(uv.x * tanHalfFov * aspect, uv.y * tanHalfFov, 1.0) );

	float3 sample = pathTrace(eye, rd, rng);

	// Progressive accumulation (reset when the scene changed).
	float4 prev  = s_accum[int2(dtid.xy)];
	float3 sum   = u_params.y > 0.5 ? sample : prev.rgb + sample;
	float  count = u_params.y > 0.5 ? 1.0    : prev.a + 1.0;
	s_accum[int2(dtid.xy)] = float4(sum, count);

	// Reinhard tonemap + gamma on the running average.
	float3 color = sum / count;
	color = color / (color + 1.0);
	color = pow(color, float3(1.0/2.2, 1.0/2.2, 1.0/2.2) );

	imageStore(s_target, ivec2(dtid.xy), float4(color, 1.0) );
}
