// Closest-hit stage of the anyhit/callable smoke phase: reads the per-instance material
// (0.25 for instance 0, 0.5 for instance 1) and invokes callable 0, which contributes
// another 0.5. Exactly 1.0 only when both any-hit filtering and the callable work.
import bgfx_shader;
import bgfx_compute;

RWStructuredBuffer<float> materials : register(u2); // stage 2

struct Payload
{
	float hit;
};

struct CallableData
{
	float add;
};

[shader("closesthit")]
void closestHitMain(inout Payload p, in BuiltInTriangleIntersectionAttributes attribs)
{
	CallableData cd;
	cd.add = 0.0;
	CallShader(0, cd);

	p.hit = materials[InstanceIndex()] + cd.add;
}
