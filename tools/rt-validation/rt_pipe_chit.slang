// Closest-hit stage of the RT-pipeline smoke test. Exercises the v2 features in one go:
//  - a resource declared ONLY in this stage (the material buffer),
//  - a binding shared with raygen (the acceleration structure),
//  - a secondary TraceRay (recursion depth 2) routed to miss index 1.
// materials[prim] = 0.75 and the secondary miss adds 0.25: payload 1.0 = full white only
// when every piece works.
import bgfx_shader;
import bgfx_compute;

uniform RaytracingAccelerationStructure scene : register(t0); // shared with raygen
RWStructuredBuffer<float> materials : register(u2);           // declared in this stage only

struct Payload
{
	float hit;
};

[shader("closesthit")]
void closestHitMain(inout Payload p, in BuiltInTriangleIntersectionAttributes attribs)
{
	float mat = materials[PrimitiveIndex()];

	RayDesc rd;
	rd.Origin    = WorldRayOrigin() + WorldRayDirection() * RayTCurrent();
	rd.Direction = float3(0, 0, 1);
	rd.TMin      = 1e-3;
	rd.TMax      = 1000.0;

	Payload p2;
	p2.hit = 0.0;
	TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 0, 1, rd, p2); // miss shader index 1

	p.hit = mat + p2.hit;
}
