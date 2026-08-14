// Closest-hit stage of the RT-pipeline render stage: per-material shading in the hit
// shader -- the pattern the ray-tracing pipeline exists for. Reads the same per-triangle
// material table as the ray-query tracer (instance*12 + primitive), rotates box-instance
// normals by the payload's angle, and fires a shadow ray toward the light centre with
// RAY_FLAG_SKIP_CLOSEST_HIT_SHADER (no recursion past depth 2; only the shadow miss and
// the any-hit stage run). The lighting model matches the "Simple RT" stage exactly, down
// to emitters not occluding -- see rt_cornellbox_ahit.slang.
import bgfx_shader;
import bgfx_compute;
import "cornellbox.sh";

uniform RaytracingAccelerationStructure scene : register(t0); // shared with raygen

struct Material
{
	float4 albedo;   // xyz
	float4 emission; // xyz
	float4 normal;   // xyz, inward-facing, in BLAS-local space
};
RWStructuredBuffer<Material> materials : register(u3); // stage 3 (chit-only)

[shader("closesthit")]
void closestHitMain(inout RtPipePayload p, in BuiltInTriangleIntersectionAttributes attribs)
{
	uint matIdx = InstanceIndex()*12 + PrimitiveIndex();
	Material m = materials[matIdx];

	float3 emission = m.emission.xyz;
	if (dot(emission, emission) > 0.0)
	{
		p.color = emission;
		return;
	}

	float3 n = m.normal.xyz;
	uint inst = InstanceIndex();
	if (inst == 1u) n = rotY(n,  p.angle);
	if (inst == 2u) n = rotY(n, -p.angle);

	float3 hitP = WorldRayOrigin() + WorldRayDirection()*RayTCurrent();
	float3 toLight = kLightCenter - hitP;
	float dist = length(toLight);
	float3 wi = toLight / dist;

	float ndotl = max(0.0, dot(n, wi) );
	float3 albedo = m.albedo.xyz;
	float3 color = albedo * 0.12; // ambient

	if (ndotl > 0.0)
	{
		RayDesc rd;
		rd.Origin    = hitP + n*kShadowBias;
		rd.Direction = wi;
		rd.TMin      = 1e-3;
		rd.TMax      = dist - kShadowBias;

		RtShadowPayload sp;
		sp.lit = 0.0;
		// FORCE_NON_OPAQUE so the any-hit stage runs: bgfx builds BLAS geometry opaque,
		// which would otherwise skip it. Any-hit rejects emissive hits, matching the
		// ray-query tracer's occluded() -- without it the light's own quad shadows the
		// surfaces around it. ACCEPT_FIRST_HIT still ends the search on the first hit
		// any-hit accepts, so this stays a cheap boolean visibility ray.
		TraceRay(scene
			, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH | RAY_FLAG_SKIP_CLOSEST_HIT_SHADER
			| RAY_FLAG_FORCE_NON_OPAQUE
			, 0xff, 0, 0, 1, rd, sp);

		color += albedo * kLightEmission * (ndotl / (dist*dist) ) * 0.15 * sp.lit;
	}

	p.color = color;
}
