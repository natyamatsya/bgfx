// Closest-hit stage of the procedural smoke phase: 0.5 for the hit itself plus 0.5 when
// the intersection shader's reported t matches the analytic sphere entry (5 - 0.8 = 4.2)
// -- full white only when the procedural hit group works end to end.
struct Payload
{
	float hit;
};

struct SphereAttr
{
	float2 unused;
};

[shader("closesthit")]
void closestHitMain(inout Payload p, in SphereAttr attr)
{
	p.hit = 0.5;
	if (abs(RayTCurrent() - 4.2) < 0.01)
	{
		p.hit += 0.5;
	}
}
