// Cornell Box, ray traced with hardware ray query (Slang).
//
// This is the *RT-accelerated* path, selected when BGFX_CAPS_RAY_TRACING is present. The
// geometry is three BLASes (walls+light, tall box, short box) instanced by a TLAS; the two
// box instances rotate via bgfx::updateTlas. The example exposes three render stages
// (u_params.w), sharing this one scene:
//
//   0 Simple RT -- deterministic direct lighting (light centre + hard shadow + ambient).
//     No noise, no accumulation: the baseline "ray tracing works" stage.
//   1 Simple PT -- progressive path tracer (NEE + cosine-weighted diffuse bounces)
//     accumulated in s_accum; noisy at 1 spp while the scene moves.
//   2 PT + denoiser -- same path tracer, but the demodulated irradiance and a primary-hit
//     G-buffer (albedo, normal+depth) are written for the a-trous filter passes
//     (cs_cornellbox_atrous.slang) that produce the display image.
//
// The analytic compute fallback (cs_cornellbox.slang) implements the same stages without
// hardware RT.
import bgfx_shader;
import bgfx_compute;
import "cornellbox.sh";

// bgfx flattens the t/u register spaces into one bind namespace, so the register NUMBERS
// must be globally unique across resources (stage = register - 0 base, in decl order).
uniform RaytracingAccelerationStructure scene : register(t0); // stage 0

RWTexture2D<float4> s_accum   : register(u1); // stage 1: rgb = radiance sum, a = sample count
RWTexture2D<float4> s_target  : register(u2); // stage 2: tonemapped display image
RWTexture2D<float4> s_gbufA   : register(u4); // stage 4: primary-hit albedo (mode 2)
RWTexture2D<float4> s_gbufN   : register(u5); // stage 5: primary-hit normal.xyz + t (mode 2)
RWTexture2D<float4> s_irr     : register(u6); // stage 6: demodulated irradiance (mode 2)

struct Material
{
	float4 albedo;   // xyz
	float4 emission; // xyz
	float4 normal;   // xyz, inward-facing, in BLAS-local space
};
RWStructuredBuffer<Material> materials : register(u3); // stage 3

// x = frame index (RNG seed), y = reset accumulation (>0.5), z = box rotation angle,
// w = render stage (0 = simple RT, 1 = simple PT, 2 = PT + denoiser).
uniform float4 u_params;

// x = samples per pixel per frame, y = max path bounces (quality vs frame-time controls).
uniform float4 u_ptParams;

static const uint kTrisPerInstance = 12;

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

// --- stage 0: simple RT (deterministic direct lighting) ---------------------------------

float3 directLight(float3 ro, float3 rd)
{
	float t;
	int matIdx = traceClosest(ro, rd, 1e30, t);
	if (matIdx < 0) return float3(0.02, 0.02, 0.02);

	Material m = materials[matIdx];
	float3 emission = m.emission.xyz;
	if (dot(emission, emission) > 0.0) return emission;

	float3 albedo = m.albedo.xyz;
	float3 n = hitNormal(matIdx);
	float3 p = ro + t*rd;

	float3 toLight = kLightCenter - p;
	float dist = length(toLight);
	float3 wi = toLight / dist;

	float ndotl = max(0.0, dot(n, wi) );
	float3 ambient = albedo * 0.12;
	float3 direct  = float3(0, 0, 0);
	if (ndotl > 0.0 && !occluded(p + n*kShadowBias, wi, dist) )
	{
		direct = albedo * kLightEmission * (ndotl / (dist*dist) ) * 0.15;
	}
	return ambient + direct;
}

// --- stages 1+2: path tracing ------------------------------------------------------------

float3 pathTrace(float3 ro, float3 rd, inout uint rng, out Primary prim)
{
	float3 radiance   = float3(0, 0, 0);
	float3 throughput = float3(1, 1, 1);
	prim.albedo = float3(1, 1, 1);
	prim.normal = float3(0, 0, 0);
	prim.t      = 0.0;
	prim.inst   = 0;

	const int maxBounces = clamp(int(u_ptParams.y), 1, 8);
	for (int bounce = 0; bounce < maxBounces; ++bounce)
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

		if (bounce == 0)
		{
			prim.albedo = albedo;
			prim.normal = n;
			prim.t      = t;
			prim.inst   = int(uint(matIdx) / kTrisPerInstance);
		}

		// Next-event estimation: sample a point on the area light.
		float3 lp = sampleLightPoint(rng);
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

	const int mode = int(u_params.w);

	uint rng = pcgHash(dtid.y*9781u + dtid.x + pcgHash(uint(u_params.x)*2971u) );

	if (mode == 0)
	{
		// Simple RT: deterministic, no accumulation.
		float3 rd0 = primaryRay(float2(dtid.xy), float2(0.5, 0.5), res);
		imageStore(s_target, ivec2(dtid.xy), float4(tonemap(directLight(kEye, rd0) ), 1.0) );
		return;
	}

	// N sub-pixel-jittered paths per frame (quality vs frame-time control).
	const int spp = clamp(int(u_ptParams.x), 1, 64);
	Primary prim;
	float3 sampleSum = float3(0, 0, 0);
	for (int s = 0; s < spp; ++s)
	{
		float2 jitter = float2(rnd(rng), rnd(rng) );
		float3 rd = primaryRay(float2(dtid.xy), jitter, res);
		Primary p;
		sampleSum += pathTrace(kEye, rd, rng, p);
		if (s == 0) prim = p;
	}

	if (mode == 1)
	{
		// Progressive accumulation (reset when the scene changed).
		float4 prev  = s_accum[int2(dtid.xy)];
		float3 sum   = u_params.y > 0.5 ? sampleSum : prev.rgb + sampleSum;
		float  count = u_params.y > 0.5 ? float(spp) : prev.a + float(spp);
		s_accum[int2(dtid.xy)] = float4(sum, count);
		imageStore(s_target, ivec2(dtid.xy), float4(tonemap(sum / count), 1.0) );
		return;
	}

	// Mode 2: write the G-buffer and THIS FRAME's albedo-demodulated irradiance (plus the
	// instance id for reprojection); the temporal pass owns the accumulation, the a-trous
	// passes filter it, and the final pass produces the display image.
	float3 fresh = (sampleSum / float(spp)) / max(prim.albedo, float3(1e-3, 1e-3, 1e-3) );
	s_gbufA[int2(dtid.xy)] = float4(prim.albedo, 1.0);
	s_gbufN[int2(dtid.xy)] = float4(prim.normal, prim.t);
	s_irr[int2(dtid.xy)]   = float4(fresh, float(prim.inst) );
}
