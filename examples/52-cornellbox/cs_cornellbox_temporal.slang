// Temporal reprojection pass (Slang) -- the accumulation stage of the "PT + denoiser"
// pipeline (SVGF-style). For every pixel, the primary-hit world position is reprojected to
// where that surface point was LAST frame (the camera is static; only the two boxes rotate,
// by a known angle delta), the history irradiance is fetched there, validated against the
// current normal/depth, and blended with this frame's fresh samples. The history length N
// (stored in the history alpha channel) makes the blend a true running average up to
// kMaxHistory frames, then exponential -- so a static scene converges, and a moving scene
// keeps ~kMaxHistory frames of effective samples instead of restarting at 1 spp.
//
// Backend-independent: works on the output of either tracer.
import bgfx_shader;
import bgfx_compute;
import "cornellbox.sh";

// The history is DOUBLE-BUFFERED (read last frame's, write this frame's, the app swaps):
// reading and writing one history image in the same dispatch would race -- a pixel reads
// history at its reprojected location while another thread overwrites it -- and the
// feedback loop compounds into edge erosion and smearing under motion.
RWTexture2D<float4> s_irrCurr     : register(u0); // stage 0: fresh irradiance (w = instance id)
RWTexture2D<float4> s_histIrrPrev : register(u1); // stage 1: history irradiance in (w = history length)
RWTexture2D<float4> s_histNPrev   : register(u2); // stage 2: history normal.xyz + t in
RWTexture2D<float4> s_gbufN       : register(u3); // stage 3: current normal.xyz + t
RWTexture2D<float4> s_irrOut      : register(u4); // stage 4: blended irradiance (a-trous input)
RWTexture2D<float4> s_histIrrNew  : register(u5); // stage 5: history irradiance out
RWTexture2D<float4> s_histNNew    : register(u6); // stage 6: history normal.xyz + t out
RWTexture2D<float4> s_histMPrev   : register(u7); // stage 7: luminance moments in  (mu1, mu2)
RWTexture2D<float4> s_histMNew    : register(u8); // stage 8: luminance moments out (mu1, mu2)

// x = box rotation delta since last frame (radians), y = current box angle,
// z = reset history (>0.5).
uniform float4 u_tparams;

static const float kMaxHistory = 32.0;

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
	int2 res = imageSize(s_irrOut);
	if (int(dtid.x) >= res.x || int(dtid.y) >= res.y) return;
	const int2 px = int2(dtid.xy);

	const float4 curr = s_irrCurr[px];
	const int    inst = int(curr.w);
	const float4 gbN  = s_gbufN[px];
	const float3 n    = gbN.xyz;
	const float  t    = gbN.w;

	float3 blended = curr.rgb;
	float  histLen = 1.0;

	// Luminance moments drive the SVGF variance estimate; 3x3 spatial moments of the
	// current frame serve both the variance of young pixels and the history clamp below.
	const float lc = lum(curr.rgb);
	float m1 = lc;
	float m2 = lc*lc;

	float3 nb1 = float3(0, 0, 0);
	float3 nb2 = float3(0, 0, 0);
	float  sl1 = 0.0;
	float  sl2 = 0.0;
	for (int yy = -1; yy <= 1; ++yy)
	{
		for (int xx = -1; xx <= 1; ++xx)
		{
			const int2 np = clamp(px + int2(xx, yy), int2(0, 0), res - 1);
			const float3 c = s_irrCurr[np].rgb;
			nb1 += c;
			nb2 += c*c;
			const float l = lum(c);
			sl1 += l;
			sl2 += l*l;
		}
	}
	nb1 /= 9.0;
	nb2 /= 9.0;
	sl1 /= 9.0;
	sl2 /= 9.0;
	const float spatialVar = max(sl2 - sl1*sl1, 0.0);

	if (u_tparams.z < 0.5)
	{
		// Where was this surface point last frame? Static geometry: same place. Box
		// instances: rotate back by the per-frame delta about the box's own centre
		// (tall = +delta, short = -delta -- matching the app's transforms).
		float2 res2 = float2(res);
		float3 rd = primaryRay(float2(px), float2(0.5, 0.5), res2);
		float3 p = kEye + t*rd;

		float3 nPrev = n;
		if (inst == 1) nPrev = rotY(n, -u_tparams.x);
		if (inst == 2) nPrev = rotY(n,  u_tparams.x);

		const float2 prevPfShared = reprojectPixel(p, inst, u_tparams.x, res2);
		if (prevPfShared.x > -1e5)
		{
			// Bilinear history resample with PER-TAP validation: each of the four
			// surrounding texels must have seen (nearly) the same surface -- normal (in
			// previous-frame orientation) and view depth agree -- and only the valid taps
			// contribute with their bilinear weights. This removes the shimmer of
			// nearest-pixel resampling without ever blending across a disocclusion.
			const float2 base = floor(prevPfShared);
			const float2 fr = prevPfShared - base;
			// View depth of the reprojected point (the camera is at kEye).
			float3 pPrev = p;
			if (inst == 1) pPrev = rotY(p - kTallC,  -u_tparams.x) + kTallC;
			if (inst == 2) pPrev = rotY(p - kShortC,  u_tparams.x) + kShortC;
			const float tPrev = length(pPrev - kEye);

			const float wBil[4] = { (1.0-fr.x)*(1.0-fr.y), fr.x*(1.0-fr.y), (1.0-fr.x)*fr.y, fr.x*fr.y };
			const int2  oBil[4] = { int2(0,0), int2(1,0), int2(0,1), int2(1,1) };

			float3 histSum = float3(0, 0, 0);
			float2 momSum = float2(0, 0);
			float  lenSum = 0.0;
			float  wSum = 0.0;
			for (int i = 0; i < 4; ++i)
			{
				const int2 tp = int2(base) + oBil[i];
				if (tp.x < 0 || tp.y < 0 || tp.x >= res.x || tp.y >= res.y) continue;

				const float4 histIrr = s_histIrrPrev[tp];
				const float4 histN   = s_histNPrev[tp];
				const bool valid = dot(histN.xyz, nPrev) > 0.8
					&& abs(histN.w - tPrev) < 0.1 + 0.02*tPrev
					&& histIrr.a > 0.5;
				if (valid)
				{
					histSum += histIrr.rgb * wBil[i];
					momSum  += s_histMPrev[tp].xy * wBil[i];
					lenSum  += histIrr.a   * wBil[i];
					wSum    += wBil[i];
				}
			}

			if (wSum > 0.01)
			{
				float3 hist = histSum / wSum;

				// Variance clamp: box the history into the mean +/- gamma*sigma of the
				// current frame's 3x3 irradiance neighbourhood (nb1/nb2 above). Shading
				// that changed (e.g. a shadow cast by a moving box sweeping across a
				// wall) falls outside that range, so stale history is pulled to the new
				// value within a frame or two instead of fading over the history length.
				const float3 sigma = sqrt(max(nb2 - nb1*nb1, float3(0, 0, 0) ) );
				hist = clamp(hist, nb1 - 2.0*sigma, nb1 + 2.0*sigma);

				histLen = min(lenSum / wSum + 1.0, kMaxHistory);
				const float alpha = 1.0 / histLen;
				blended = lerp(hist, curr.rgb, alpha);

				const float2 histM = momSum / wSum;
				m1 = lerp(histM.x, lc,    alpha);
				m2 = lerp(histM.y, lc*lc, alpha);
			}
		}
	}

	// SVGF variance: temporal luminance moments, falling back to the spatial estimate
	// while the history is young (temporal moments are meaningless at 1-2 samples).
	float variance = max(m2 - m1*m1, 0.0);
	if (histLen < 4.0)
	{
		// Young history: temporal moments are meaningless at 1-2 samples. Use the spatial
		// estimate and inflate it, so the luminance edge-stop stays loose until real
		// statistics exist (otherwise 1-spp noise clumps read as "edges" and survive).
		variance = max(variance, spatialVar) * (5.0 - histLen);
	}

	s_irrOut[px]     = float4(blended, variance);
	s_histIrrNew[px] = float4(blended, histLen);
	s_histNNew[px]   = float4(n, t);
	s_histMNew[px]   = float4(m1, m2, 0.0, 0.0);
}
