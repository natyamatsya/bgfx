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

// x = samples per pixel per frame, y = max path bounces, z = box rotation delta since
// last frame (radians; for ReSTIR reservoir reprojection).
uniform float4 u_ptParams;

RWTexture2D<float4> s_resPrev : register(u7); // stage 7: ReSTIR reservoirs in  (lp.xz, W, M)
RWTexture2D<float4> s_resNew  : register(u8); // stage 8: ReSTIR reservoirs out

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


// --- stage 3: ReSTIR DI for the primary-vertex direct lighting ---------------------------
// Weighted reservoir sampling of the area-light point: 8 fresh candidates, merged with the
// reprojected previous-frame reservoir of this pixel and two jittered neighbours
// (spatiotemporal reuse). Only the final selected sample pays a visibility ray. The
// history M is clamped so stale reservoirs cannot dominate; on reset (u_params.y) reuse is
// skipped. The pixel-constant factors dropped from restirPHat are applied here.
float3 restirDirect(float3 p, float3 n, float3 albedo, int inst, int2 px, float delta, bool writeOut, inout uint rng)
{
	Reservoir r = emptyReservoir();
	float wSum = 0.0;

	for (int i = 0; i < 8; ++i)
	{
		float2 cand = float2(
			  lerp(kLightLo.x, kLightHi.x, rnd(rng))
			, lerp(kLightLo.z, kLightHi.z, rnd(rng))
			);
		streamCandidate(r, wSum, cand, restirPHat(p, n, cand), rng);
	}

	if (u_params.y < 0.5)
	{
		float2 res = float2(imageSize(s_target) );
		float2 pf = reprojectPixel(p, inst, delta, res);
		if (pf.x > -1e5)
		{
			int2 prevPx = int2(floor(pf + 0.5) );
			for (int k = 0; k < 3; ++k)
			{
				int2 tap = prevPx;
				if (k > 0)
				{
					tap += int2(int(rnd(rng)*21.0) - 10, int(rnd(rng)*21.0) - 10);
				}
				if (tap.x < 0 || tap.y < 0 || tap.x >= int(res.x) || tap.y >= int(res.y) ) continue;

				float4 e = s_resPrev[tap];
				Reservoir o;
				o.lp = e.xy;
				o.W  = e.z;
				o.M  = min(e.w, 160.0); // clamp history (20x the 8 fresh candidates)
				if (o.M > 0.0 && o.W > 0.0)
				{
					streamReservoir(r, wSum, o, restirPHat(p, n, o.lp), rng);
				}
			}
		}
	}

	float pSel = restirPHat(p, n, r.lp);
	r.W = pSel > 1e-6 ? wSum / max(r.M * pSel, 1e-6) : 0.0;

	if (writeOut)
	{
		s_resNew[px] = float4(r.lp, r.W, r.M);
	}

	if (r.W <= 0.0 || pSel <= 1e-6) return float3(0, 0, 0);

	float3 lpos = float3(r.lp.x, kLightLo.y, r.lp.y);
	float3 toL = lpos - p;
	float dist = length(toL);
	float3 wi = toL / dist;
	if (occluded(p + n*kShadowBias, wi, dist) ) return float3(0, 0, 0);

	return (albedo / kPi) * kLightEmission * (pSel * kLightArea * r.W);
}

float3 pathTrace(float3 ro, float3 rd, inout uint rng, out Primary prim, bool useRestir, int2 px)
{
	float3 radiance   = float3(0, 0, 0);
	float3 throughput = float3(1, 1, 1);
	prim.albedo   = float3(1, 1, 1);
	prim.emission = float3(0, 0, 0);
	prim.normal   = float3(0, 0, 0);
	prim.t        = 0.0;
	prim.inst     = 0;

	const int maxBounces = clamp(int(u_ptParams.y), 1, 8);
	for (int bounce = 0; bounce < maxBounces; ++bounce)
	{
		float t;
		int matIdx = traceClosest(ro, rd, 1e30, t);
		if (matIdx < 0)
		{
			if (bounce == 0)
			{
				radiance = float3(0.02, 0.02, 0.02); // open front: background
				prim.emission = radiance;
			}
			break;
		}

		Material m = materials[matIdx];
		float3 emission = m.emission.xyz;
		if (dot(emission, emission) > 0.0)
		{
			// Direct light hits only; indirect lighting is handled by NEE below.
			if (bounce == 0)
			{
				radiance += throughput * emission;
				prim.emission = emission;
			}
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

		// Direct lighting: ReSTIR at the primary vertex in stage 3, otherwise NEE.
		if (bounce == 0 && useRestir)
		{
			radiance += throughput * restirDirect(p, n, albedo, prim.inst, px, u_ptParams.z, true, rng);
			rd = cosineSample(n, rnd(rng), rnd(rng) );
			ro = p + n*kShadowBias;
			throughput *= albedo;
			continue;
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
	const bool useRestir = mode == 3;

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
		// Sample 0 uses the pixel centre: it supplies the G-buffer and the emitter
		// visibility, which must be deterministic per pixel or the emitter's edges crawl
		// with the jitter. The remaining samples are jittered as usual.
		float2 jitter = s == 0 ? float2(0.5, 0.5) : float2(rnd(rng), rnd(rng) );
		float3 rd = primaryRay(float2(dtid.xy), jitter, res);
		Primary p;
		sampleSum += pathTrace(kEye, rd, rng, p, useRestir && s == 0, int2(dtid.xy) );
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
	// Directly-visible emission (the light itself, and the background) is NOT part of the
	// denoised signal: its raw radiance would dominate the variance at the emitter's edges
	// and make the filter smear it. It is stored in the G-buffer (flagged in gbufA.a) and
	// composited after filtering by the final a-trous pass.
	const bool passthrough = dot(prim.emission, prim.emission) > 0.0;
	float3 fresh = passthrough
		? float3(0, 0, 0)
		: (sampleSum / float(spp)) / max(prim.albedo, float3(1e-3, 1e-3, 1e-3) );
	s_gbufA[int2(dtid.xy)] = passthrough ? float4(prim.emission, 1.0) : float4(prim.albedo, 0.0);
	s_gbufN[int2(dtid.xy)] = float4(prim.normal, prim.t);
	s_irr[int2(dtid.xy)]   = float4(fresh, float(prim.inst) );
}
