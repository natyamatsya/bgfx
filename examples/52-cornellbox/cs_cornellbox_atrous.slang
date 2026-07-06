// Edge-aware a-trous wavelet filter pass (Slang) -- the denoiser of the "PT + denoiser"
// stage (SVGF-style, spatial only). Runs several times with doubling step size on the
// albedo-demodulated irradiance written by the tracer; edges are preserved by weighting
// taps with the primary-hit normal and depth from the G-buffer. The final pass re-modulates
// the albedo and tonemaps into the display image.
//
// Backend-independent: the same pass filters the output of both the hardware ray-query
// tracer and the analytic compute fallback.
import bgfx_shader;
import bgfx_compute;
import "cornellbox.sh";

RWTexture2D<float4> s_irrIn  : register(u0); // stage 0: irradiance in
RWTexture2D<float4> s_irrOut : register(u1); // stage 1: irradiance out
RWTexture2D<float4> s_gbufN  : register(u2); // stage 2: normal.xyz + t
RWTexture2D<float4> s_gbufA  : register(u3); // stage 3: albedo
RWTexture2D<float4> s_target : register(u4); // stage 4: display image (final pass)

// x = step size (1, 2, 4, ...), y = final pass (>0.5: modulate albedo + tonemap into
// s_target instead of writing s_irrOut).
uniform float4 u_filterParams;

static const float kSigmaNormal = 32.0;  // normal edge-stopping power
static const float kSigmaDepth  = 2.0;   // depth edge-stopping falloff (gradient-scaled)
static const float kSigmaLum    = 4.0;   // luminance edge-stopping falloff (variance-scaled)

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
	int2 res = imageSize(s_target);
	if (int(dtid.x) >= res.x || int(dtid.y) >= res.y) return;

	const int2 center = int2(dtid.xy);
	const int  step   = int(u_filterParams.x);

	const float4 gbC = s_gbufN[center];
	const float3 nC  = gbC.xyz;
	const float  tC  = gbC.w;

	// Local depth gradient (one-sided differences; min picks the CONTINUOUS side at
	// silhouettes). The depth tolerance scales with this gradient and the tap distance:
	// a face parallel to the image plane has ~zero gradient, so even the widest filter
	// steps stay depth-tight -- without this, an axis-aligned box front (whose normal
	// exactly matches the wall behind it) blends into the wall and visually erodes.
	const int2 pxE = int2(min(center.x+1, res.x-1), center.y);
	const int2 pxW = int2(max(center.x-1, 0),       center.y);
	const int2 pxS = int2(center.x, min(center.y+1, res.y-1) );
	const int2 pxN = int2(center.x, max(center.y-1, 0) );
	const float gx = min(abs(s_gbufN[pxE].w - tC), abs(tC - s_gbufN[pxW].w) );
	const float gy = min(abs(s_gbufN[pxS].w - tC), abs(tC - s_gbufN[pxN].w) );
	const float gradT = max(max(gx, gy), 1e-4);

	// SVGF: the luminance edge-stopping tolerance scales with the local noise level --
	// sqrt of a 3x3 gaussian prefilter of the variance channel (irradiance alpha). Where
	// the signal has converged the filter stops smoothing; where it is noisy it blurs.
	const float4 irrC = s_irrIn[center];
	const float lumC = lum(irrC.rgb);
	float varG = 0.0;
	{
		const float g[3] = { 0.25, 0.5, 0.25 };
		for (int yy = -1; yy <= 1; ++yy)
		{
			for (int xx = -1; xx <= 1; ++xx)
			{
				const int2 np = clamp(center + int2(xx, yy), int2(0, 0), res - 1);
				varG += s_irrIn[np].a * g[xx+1]*g[yy+1];
			}
		}
	}
	const float lumDenom = kSigmaLum * sqrt(max(varG, 0.0) ) + 1e-4;

	// 5x5 B3-spline kernel (separable 1/16, 1/4, 3/8, 1/4, 1/16), taps spaced by `step`.
	const float kernel1d[5] = { 1.0/16.0, 1.0/4.0, 3.0/8.0, 1.0/4.0, 1.0/16.0 };

	float3 sum = float3(0, 0, 0);
	float  varSum = 0.0;
	float  wsum = 0.0;

	for (int yy = -2; yy <= 2; ++yy)
	{
		for (int xx = -2; xx <= 2; ++xx)
		{
			int2 tap = center + int2(xx, yy)*step;
			if (tap.x < 0 || tap.y < 0 || tap.x >= res.x || tap.y >= res.y) continue;

			const float4 gbP = s_gbufN[tap];
			const float3 nP  = gbP.xyz;
			const float  tP  = gbP.w;
			const float4 irrP = s_irrIn[tap];

			// Edge-stopping weights: normals (background pixels have n=0 and only pass the
			// centre tap), primary-hit depth with a gradient-scaled tolerance, and
			// luminance with a variance-scaled tolerance (SVGF).
			const float wN = pow(max(0.0, dot(nC, nP) ), kSigmaNormal);
			const float distPx = float(step) * sqrt(float(xx*xx + yy*yy) );
			const float wZ = exp(-abs(tC - tP) / (kSigmaDepth * gradT * distPx + 1e-2) );
			const float wL = exp(-abs(lum(irrP.rgb) - lumC) / lumDenom);
			const float w  = kernel1d[xx+2]*kernel1d[yy+2] * (xx == 0 && yy == 0 ? 1.0 : wN*wZ*wL);

			sum    += irrP.rgb * w;
			varSum += irrP.a * w*w;
			wsum   += w;
		}
	}

	const float3 filtered = sum / max(wsum, 1e-6);

	if (u_filterParams.y > 0.5)
	{
		// Final pass: re-modulate the primary-hit albedo and tonemap for display.
		const float3 albedo = s_gbufA[center].rgb;
		imageStore(s_target, ivec2(center), float4(tonemap(filtered * albedo), 1.0) );
	}
	else
	{
		// Propagate the variance through the filter (SVGF: var' = sum w^2 var / (sum w)^2)
		// so later, wider passes see how much noise remains.
		s_irrOut[center] = float4(filtered, varSum / max(wsum*wsum, 1e-6) );
	}
}
