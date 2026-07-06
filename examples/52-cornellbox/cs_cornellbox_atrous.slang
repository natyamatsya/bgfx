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

RWTexture2D<float4> s_irrIn  : register(u0); // stage 0: irradiance in
RWTexture2D<float4> s_irrOut : register(u1); // stage 1: irradiance out
RWTexture2D<float4> s_gbufN  : register(u2); // stage 2: normal.xyz + t
RWTexture2D<float4> s_gbufA  : register(u3); // stage 3: albedo
RWTexture2D<float4> s_target : register(u4); // stage 4: display image (final pass)

// x = step size (1, 2, 4, ...), y = final pass (>0.5: modulate albedo + tonemap into
// s_target instead of writing s_irrOut).
uniform float4 u_filterParams;

static const float kSigmaNormal = 32.0;  // normal edge-stopping power
static const float kSigmaDepth  = 0.7;   // depth edge-stopping falloff

float3 tonemap(float3 color)
{
	color = color / (color + 1.0);
	return pow(color, float3(1.0/2.2, 1.0/2.2, 1.0/2.2) );
}

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

	// 5x5 B3-spline kernel (separable 1/16, 1/4, 3/8, 1/4, 1/16), taps spaced by `step`.
	const float kernel1d[5] = { 1.0/16.0, 1.0/4.0, 3.0/8.0, 1.0/4.0, 1.0/16.0 };

	float3 sum = float3(0, 0, 0);
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

			// Edge-stopping weights: normals (background pixels have n=0 and only pass the
			// centre tap) and primary-hit depth.
			const float wN = pow(max(0.0, dot(nC, nP) ), kSigmaNormal);
			const float wZ = exp(-abs(tC - tP) / (kSigmaDepth*float(step) + 1e-3) );
			const float w  = kernel1d[xx+2]*kernel1d[yy+2] * (xx == 0 && yy == 0 ? 1.0 : wN*wZ);

			sum  += s_irrIn[tap].rgb * w;
			wsum += w;
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
		s_irrOut[center] = float4(filtered, 1.0);
	}
}
