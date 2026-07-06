// Shared module for the Cornell Box shaders: the scene-wide constants (camera, light, box
// placement) and the math helpers used by the tracers (cs_cornellbox_rq / cs_cornellbox),
// the temporal pass, and the a-trous filter. Single source of truth -- these constants used
// to be duplicated per shader (and drifting copies of e.g. the box centres or the camera
// would produce silently wrong reprojection).
module "cornellbox.sh";

public static const float kPi = 3.14159265;

// --- camera (a fixed pinhole at the open front of the box) -------------------------------

public static const float3 kEye = float3(0.0, 0.0, -3.8);
public static const float  kTanHalfFov = tan(kPi * 40.0 / 180.0 * 0.5);

// Primary ray direction through pixel `px` + `subPixel` for an image of size `res`.
// Image Y is top-down, so flip to a Y-up camera.
public float3 primaryRay(float2 px, float2 subPixel, float2 res)
{
	float2 uv = (px + subPixel) / res * 2.0 - 1.0;
	uv.y = -uv.y;
	float aspect = res.x / res.y;
	return normalize(float3(uv.x * kTanHalfFov * aspect, uv.y * kTanHalfFov, 1.0) );
}

// --- the area light on the ceiling --------------------------------------------------------

public static const float3 kLightLo = float3(-0.35, 0.997, -0.35);
public static const float3 kLightHi = float3( 0.35, 0.997,  0.35);
public static const float3 kLightCenter = float3(0.0, 0.997, 0.0);
public static const float3 kLightEmission = float3(18.0, 18.0, 18.0);
public static const float  kLightArea = 0.7 * 0.7;

// --- the two boxes (rotate about their own centres; must match the app's TLAS transforms) -

public static const float3 kTallC  = float3(-0.37, 0.0,  0.15);
public static const float3 kShortC = float3( 0.35, 0.0, -0.30);

public static const float kShadowBias = 4e-3;

// --- RNG (PCG) ----------------------------------------------------------------------------

public uint pcgHash(uint v)
{
	v = v*747796405u + 2891336453u;
	uint w = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
	return (w >> 22u) ^ w;
}

public float rnd(inout uint state)
{
	state = pcgHash(state);
	return float(state) * (1.0 / 4294967296.0);
}

// Uniform point on the area light.
public float3 sampleLightPoint(inout uint rng)
{
	return float3(
		  lerp(kLightLo.x, kLightHi.x, rnd(rng))
		, kLightLo.y
		, lerp(kLightLo.z, kLightHi.z, rnd(rng))
		);
}

// --- geometry / shading helpers ------------------------------------------------------------

// Rotation about Y matching bx::mtxRotateY's (row-vector) convention.
public float3 rotY(float3 v, float a)
{
	float c = cos(a), s = sin(a);
	return float3(c*v.x - s*v.z, v.y, s*v.x + c*v.z);
}

public float3 cosineSample(float3 n, float u1, float u2)
{
	float ang = 2.0*kPi*u1;
	float r = sqrt(u2);
	float3 t = normalize(cross(abs(n.y) < 0.99 ? float3(0,1,0) : float3(1,0,0), n) );
	float3 b = cross(n, t);
	return normalize(t*(r*cos(ang)) + b*(r*sin(ang)) + n*sqrt(max(0.0, 1.0 - u2)) );
}

public float lum(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722) ); }

// Reinhard tonemap + gamma, shared by every pass that writes the display image.
public float3 tonemap(float3 color)
{
	color = color / (color + 1.0);
	return pow(color, float3(1.0/2.2, 1.0/2.2, 1.0/2.2) );
}

// Reproject a world-space point to the previous frame's pixel coordinate (pixel-centre
// units; the caller rounds or bilinearly samples). The camera is static; only the two box
// instances move, by `delta` radians about their own centres (tall = +, short = -).
// Returns x = -1e6 when the point was behind the camera.
public float2 reprojectPixel(float3 p, int inst, float delta, float2 res)
{
	float3 pPrev = p;
	if (inst == 1) pPrev = rotY(p - kTallC,  -delta) + kTallC;
	if (inst == 2) pPrev = rotY(p - kShortC,  delta) + kShortC;

	float3 v = pPrev - kEye;
	if (v.z <= 1e-3) return float2(-1e6, -1e6);

	float aspect = res.x / res.y;
	float2 ndc = float2(v.x / (v.z * kTanHalfFov * aspect), v.y / (v.z * kTanHalfFov) );
	ndc.y = -ndc.y;
	return (ndc * 0.5 + 0.5) * res - 0.5;
}

// --- ReSTIR DI (weighted reservoir sampling of the area-light point) ----------------------
// The light sample is a point on the ceiling light, stored as xz (the plane is fixed).

public struct Reservoir
{
	public float2 lp; // selected light point (xz)
	public float  W;  // unbiased contribution weight
	public float  M;  // number of candidates represented
};

public Reservoir emptyReservoir()
{
	Reservoir r;
	r.lp = float2(0, 0);
	r.W = 0.0;
	r.M = 0.0;
	return r;
}

// Target pdf p-hat: the geometry term of light point `lp` seen from surface (p, n). The
// pixel-constant factors (albedo, emission, light area) cancel out of W and are applied
// at shading time.
public float restirPHat(float3 p, float3 n, float2 lp)
{
	float3 lpos = float3(lp.x, kLightLo.y, lp.y);
	float3 toL = lpos - p;
	float d2 = dot(toL, toL);
	float dist = sqrt(d2);
	float3 wi = toL / dist;
	return max(0.0, dot(n, wi) ) * max(0.0, wi.y) / max(d2, 1e-4);
}

// Stream one candidate (weight w) into the reservoir.
public void streamCandidate(inout Reservoir r, inout float wSum, float2 cand, float w, inout uint rng)
{
	wSum += w;
	r.M += 1.0;
	if (rnd(rng) * wSum < w)
	{
		r.lp = cand;
	}
}

// Merge another reservoir, re-weighting its sample by the target pdf at the CURRENT surface.
public void streamReservoir(inout Reservoir r, inout float wSum, Reservoir other, float pHatHere, inout uint rng)
{
	float w = pHatHere * other.W * other.M;
	wSum += w;
	r.M += other.M;
	if (rnd(rng) * wSum < w)
	{
		r.lp = other.lp;
	}
}

// Primary-hit info for the G-buffer / demodulation (denoiser stage).
public struct Primary
{
	public float3 albedo;   // 1 for miss/emissive (modulation becomes identity)
	public float3 emission; // non-zero for emissive/background primaries: displayed directly,
	                        // NOT run through accumulation/filtering (see the atrous resolve)
	public float3 normal;
	public float  t;
	public int    inst;   // 0 static, 1 tall box, 2 short box (for temporal reprojection)
};
