// Cornell Box, ray traced in a compute shader (Slang).
//
// This is the *compute fallback* path: a self-contained analytic tracer that runs anywhere
// compute is supported, with no hardware ray tracing. It implements the same three render
// stages as the RT-accelerated ray-query path (cs_cornellbox_rq.slang), selected by
// u_params.w:
//
//   0 Simple RT -- deterministic direct lighting (light centre + hard shadow + ambient).
//   1 Simple PT -- progressive path tracer (NEE + cosine-weighted diffuse bounces).
//   2 PT + denoiser -- the path tracer writing demodulated irradiance + a primary-hit
//     G-buffer for the a-trous filter passes (cs_cornellbox_atrous.slang).
//
// The two boxes rotate about their own axes (u_params.z) when the rotation mode is on.
import bgfx_shader;
import bgfx_compute;
import "cornellbox.sh";

RWTexture2D<float4> s_accum  : register(u0); // stage 0: rgb = radiance sum, a = sample count
RWTexture2D<float4> s_target : register(u1); // stage 1: tonemapped display image
RWTexture2D<float4> s_gbufA  : register(u2); // stage 2: primary-hit albedo (mode 2)
RWTexture2D<float4> s_gbufN  : register(u3); // stage 3: primary-hit normal.xyz + t (mode 2)
RWTexture2D<float4> s_irr    : register(u4); // stage 4: demodulated irradiance (mode 2)

// x = frame index (RNG seed), y = reset accumulation (>0.5), z = box rotation angle,
// w = render stage (0 = simple RT, 1 = simple PT, 2 = PT + denoiser).
uniform float4 u_params;

// x = samples per pixel per frame, y = max path bounces, z = box rotation delta since
// last frame (radians; for ReSTIR reservoir reprojection).
uniform float4 u_ptParams;

RWTexture2D<float4> s_resPrev : register(u5); // stage 5: ReSTIR reservoirs in  (lp.xz, W, M)
RWTexture2D<float4> s_resNew  : register(u6); // stage 6: ReSTIR reservoirs out

static const float kInf = 1e30;
static const float kEps = 1e-3;

struct Hit
{
	float  t;
	float3 n;
	float3 albedo;
	float3 emission;
	int    inst; // 0 static, 1 tall box, 2 short box (for temporal reprojection)
};

// --- analytic scene ---------------------------------------------------------------------

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
	best.t = t; best.n = n; best.albedo = albedo; best.emission = emission; best.inst = 0;
}

// Ray vs axis-aligned box [lo,hi] in LOCAL space; returns t and local-space normal.
bool hitBoxLocal(float3 ro, float3 rd, float3 lo, float3 hi, float tMax, out float tHit, out float3 n)
{
	float3 inv = 1.0 / rd;
	float3 t0 = (lo - ro) * inv;
	float3 t1 = (hi - ro) * inv;
	float3 tsmall = min(t0, t1);
	float3 tbig   = max(t0, t1);
	float tNear = max(max(tsmall.x, tsmall.y), tsmall.z);
	float tFar  = min(min(tbig.x,  tbig.y),  tbig.z);
	tHit = 0.0; n = float3(0, 0, 0);
	if (tNear > tFar || tFar < kEps) return false;
	float t = tNear > kEps ? tNear : tFar;
	if (t >= tMax) return false;
	// Face normal: the slab that produced tNear.
	if      (tsmall.x == tNear) n = float3(rd.x > 0 ? -1 : 1, 0, 0);
	else if (tsmall.y == tNear) n = float3(0, rd.y > 0 ? -1 : 1, 0);
	else                        n = float3(0, 0, rd.z > 0 ? -1 : 1);
	tHit = t;
	return true;
}

// Ray vs a box rotated by `angle` about Y around centre c (matches the RT path's TLAS
// instance transforms): trace in the box's local frame, rotate the normal back out.
void hitOBB(float3 ro, float3 rd, float3 c, float3 lo, float3 hi, float angle, float3 albedo, int inst, inout Hit best)
{
	float3 roL = rotY(ro - c, -angle);
	float3 rdL = rotY(rd, -angle);
	float t; float3 nL;
	if (hitBoxLocal(roL, rdL, lo, hi, best.t, t, nL) )
	{
		best.t = t; best.n = rotY(nL, angle); best.albedo = albedo; best.emission = float3(0, 0, 0); best.inst = inst;
	}
}

static const float3 kWhite = float3(0.73, 0.73, 0.73);
static const float3 kRed   = float3(0.65, 0.05, 0.05);
static const float3 kGreen = float3(0.12, 0.45, 0.15);

// The two boxes, authored in local space centred (in xz) on their world positions
// (centres kTallC / kShortC come from cornellbox_common).
static const float3 kTallLo = float3(-0.25, -1.0, -0.25);
static const float3 kTallHi = float3( 0.25,  0.3,  0.25);
static const float3 kShortLo = float3(-0.25, -1.0, -0.25);
static const float3 kShortHi = float3( 0.25, -0.4,  0.25);

Hit sceneHit(float3 ro, float3 rd)
{
	Hit best; best.t = kInf; best.n = float3(0,0,0); best.albedo = float3(0,0,0); best.emission = float3(0,0,0); best.inst = 0;

	// Walls (interior of a [-1,1]^3 box, open front at z=-1).
	hitQuad(ro, rd, 1, -1.0, float3(-1,-1,-1), float3(1,-1,1), float3(0, 1, 0), kWhite, float3(0,0,0), best); // floor
	hitQuad(ro, rd, 1,  1.0, float3(-1, 1,-1), float3(1, 1,1), float3(0,-1, 0), kWhite, float3(0,0,0), best); // ceiling
	hitQuad(ro, rd, 2,  1.0, float3(-1,-1, 1), float3(1, 1,1), float3(0, 0,-1), kWhite, float3(0,0,0), best); // back
	hitQuad(ro, rd, 0, -1.0, float3(-1,-1,-1), float3(-1,1,1), float3(1, 0, 0), kRed,   float3(0,0,0), best); // left
	hitQuad(ro, rd, 0,  1.0, float3( 1,-1,-1), float3(1, 1,1), float3(-1,0, 0), kGreen, float3(0,0,0), best); // right

	// Area light (slightly below the ceiling).
	hitQuad(ro, rd, 1, 0.998, kLightLo, kLightHi, float3(0,-1,0), float3(0,0,0), kLightEmission, best);

	// Two boxes, rotating about their own axes in rotation mode.
	hitOBB(ro, rd, kTallC,  kTallLo,  kTallHi,   u_params.z, kWhite, 1, best); // tall
	hitOBB(ro, rd, kShortC, kShortLo, kShortHi, -u_params.z, kWhite, 2, best); // short

	return best;
}

bool occluded(float3 ro, float3 rd, float maxT)
{
	// An occluder must be strictly between the surface and the light; the light itself
	// (emissive) and anything at/behind it does not shadow.
	Hit h = sceneHit(ro, rd);
	return h.t < maxT - kShadowBias && dot(h.emission, h.emission) <= 0.0;
}

// --- stage 0: simple RT (deterministic direct lighting) ---------------------------------

float3 directLight(float3 ro, float3 rd)
{
	Hit h = sceneHit(ro, rd);
	if (h.t >= kInf) return float3(0.02, 0.02, 0.02);
	if (dot(h.emission, h.emission) > 0.0) return h.emission;

	float3 p = ro + h.t*rd;
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
	return ambient + direct;
}

// --- stages 1+2: path tracing (same estimator as the RT path) ----------------------------


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
	prim.albedo = float3(1, 1, 1);
	prim.normal = float3(0, 0, 0);
	prim.t      = 0.0;
	prim.inst   = 0;

	const int maxBounces = clamp(int(u_ptParams.y), 1, 8);
	for (int bounce = 0; bounce < maxBounces; ++bounce)
	{
		Hit h = sceneHit(ro, rd);
		if (h.t >= kInf)
		{
			if (bounce == 0) radiance = float3(0.02, 0.02, 0.02); // open front: background
			break;
		}

		if (dot(h.emission, h.emission) > 0.0)
		{
			// Direct light hits only; indirect lighting is handled by NEE below.
			if (bounce == 0) radiance += throughput * h.emission;
			break;
		}

		float3 p = ro + h.t*rd;

		if (bounce == 0)
		{
			prim.albedo = h.albedo;
			prim.normal = h.n;
			prim.t      = h.t;
			prim.inst   = h.inst;
		}

		// Direct lighting: ReSTIR at the primary vertex in stage 3, otherwise NEE.
		if (bounce == 0 && useRestir)
		{
			radiance += throughput * restirDirect(p, h.n, h.albedo, h.inst, px, u_ptParams.z, true, rng);
			rd = cosineSample(h.n, rnd(rng), rnd(rng) );
			ro = p + h.n*kShadowBias;
			throughput *= h.albedo;
			continue;
		}

		// Next-event estimation: sample a point on the area light.
		float3 lp = sampleLightPoint(rng);
		float3 toL = lp - p;
		float d2 = dot(toL, toL);
		float dist = sqrt(d2);
		float3 wi = toL / dist;
		float ndotl = dot(h.n, wi);
		float lndotl = wi.y; // dot(lightNormal=(0,-1,0), -wi)
		if (ndotl > 0.0 && lndotl > 0.0 && !occluded(p + h.n*kShadowBias, wi, dist) )
		{
			radiance += throughput * (h.albedo / kPi) * kLightEmission * (ndotl * lndotl / d2) * kLightArea;
		}

		// Cosine-weighted diffuse bounce; BRDF/pdf leaves just the albedo.
		rd = cosineSample(h.n, rnd(rng), rnd(rng) );
		ro = p + h.n*kShadowBias;
		throughput *= h.albedo;
	}

	return radiance;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
	// Resolution comes from the output image itself -- no uniform needed.
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
		float2 jitter = float2(rnd(rng), rnd(rng) );
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
	float3 fresh = (sampleSum / float(spp)) / max(prim.albedo, float3(1e-3, 1e-3, 1e-3) );
	s_gbufA[int2(dtid.xy)] = float4(prim.albedo, 1.0);
	s_gbufN[int2(dtid.xy)] = float4(prim.normal, prim.t);
	s_irr[int2(dtid.xy)]   = float4(fresh, float(prim.inst) );
}
