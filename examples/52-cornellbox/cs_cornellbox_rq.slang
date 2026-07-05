// Cornell Box, ray traced with hardware ray query (Slang).
//
// This is the *RT-accelerated* path, selected when BGFX_CAPS_RAY_TRACING is present. It
// renders the same scene as the analytic compute fallback (cs_cornellbox.slang), but the
// geometry is a real triangle mesh traced against an acceleration structure via inline ray
// query. Per-triangle materials (albedo / emission / inward normal) come from a buffer
// indexed by the committed primitive index; shading matches the fallback (direct light from
// the light centre + a hard shadow ray + a small ambient term).
import bgfx_shader;
import bgfx_compute;

// bgfx flattens the t/u register spaces into one bind namespace, so the register NUMBERS
// must be globally unique across resources or they collapse onto the same runtime bind
// stage. scene -> stage 0, s_target -> stage 1, materials -> stage 2.
uniform RaytracingAccelerationStructure scene : register(t0);

RWTexture2D<float4> s_target : register(u1);

struct Material
{
	float4 albedo;   // xyz
	float4 emission; // xyz
	float4 normal;   // xyz, inward-facing
};
RWStructuredBuffer<Material> materials : register(u2);

static const float3 kLightCenter = float3(0.0, 0.997, 0.0);
static const float  kShadowBias  = 4e-3;

// Closest hit: returns primitive index, or -1 on miss. t is written back.
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
		return rq.CommittedPrimitiveIndex();
	}
	tHit = tmax;
	return -1;
}

// True if a non-emissive surface lies strictly between the point and the light.
bool occluded(float3 ro, float3 rd, float maxT)
{
	float t;
	int prim = traceClosest(ro, rd, maxT, t);
	if (prim < 0) return false;
	if (t >= maxT - kShadowBias) return false;
	Material m = materials[prim];
	return dot(m.emission.xyz, m.emission.xyz) <= 0.0;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void computeMain(uint3 dtid : SV_DispatchThreadID)
{
	float2 res = float2(imageSize(s_target) );
	if (float(dtid.x) >= res.x || float(dtid.y) >= res.y) return;

	// Primary ray. Image Y is top-down, so flip to a Y-up camera (matches the fallback).
	float2 uv = (float2(dtid.xy) + 0.5) / res * 2.0 - 1.0;
	uv.y = -uv.y;
	float aspect = res.x / res.y;

	float3 eye = float3(0.0, 0.0, -3.8);
	float tanHalfFov = tan(radians(40.0) * 0.5);
	float3 rd = normalize(float3(uv.x * tanHalfFov * aspect, uv.y * tanHalfFov, 1.0) );

	float3 color = float3(0.02, 0.02, 0.02); // background

	float t;
	int prim = traceClosest(eye, rd, 1e30, t);
	if (prim >= 0)
	{
		Material m = materials[prim];
		float3 emission = m.emission.xyz;
		if (dot(emission, emission) > 0.0)
		{
			color = emission;
		}
		else
		{
			float3 albedo = m.albedo.xyz;
			float3 n = m.normal.xyz;
			float3 p = eye + t*rd;

			float3 toLight = kLightCenter - p;
			float dist = length(toLight);
			float3 wi = toLight / dist;

			float ndotl = max(0.0, dot(n, wi) );
			float3 ambient = albedo * 0.12;
			float3 direct  = float3(0, 0, 0);
			if (ndotl > 0.0 && !occluded(p + n*kShadowBias, wi, dist) )
			{
				direct = albedo * float3(18.0, 18.0, 18.0) * (ndotl / (dist*dist) ) * 0.15;
			}
			color = ambient + direct;
		}
	}

	// Reinhard tonemap + gamma (matches the fallback).
	color = color / (color + 1.0);
	color = pow(color, float3(1.0/2.2, 1.0/2.2, 1.0/2.2) );

	imageStore(s_target, ivec2(dtid.xy), float4(color, 1.0) );
}
