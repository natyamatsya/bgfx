// Ray-generation stage of the anyhit/callable smoke phase: traces with
// RAY_FLAG_FORCE_NON_OPAQUE so the any-hit stage runs (bgfx BLAS geometry is built
// opaque for ray-query auto-commit).
import bgfx_shader;
import bgfx_compute;

uniform RaytracingAccelerationStructure scene : register(t0); // stage 0
RWTexture2D<float4> s_target : register(u1);                  // stage 1

struct Payload
{
	float hit;
};

[shader("raygeneration")]
void rayGenMain()
{
	uint2 px = DispatchRaysIndex().xy;

	RayDesc rd;
	rd.Origin    = float3(0, 0, 0);
	rd.Direction = float3(0, 0, 1);
	rd.TMin      = 0.0;
	rd.TMax      = 1000.0;

	Payload p;
	p.hit = 0.0;
	TraceRay(scene, RAY_FLAG_FORCE_NON_OPAQUE, 0xff, 0, 0, 0, rd, p);

	imageStore(s_target, ivec2(px), float4(p.hit, p.hit, p.hit, 1.0) );
}
