// Intersection stage of the procedural smoke phase: analytic ray-sphere test inside the
// AABB (centre (0,0,5), radius 0.8). Reports the entry point; the closest-hit stage
// validates the reported t.
struct SphereAttr
{
	float2 unused;
};

[shader("intersection")]
void intersectMain()
{
	float3 c  = float3(0.0, 0.0, 5.0);
	float  r  = 0.8;
	float3 ro = ObjectRayOrigin();
	float3 rd = ObjectRayDirection();

	float3 oc = ro - c;
	float a = dot(rd, rd);
	float b = dot(oc, rd);
	float d = b*b - a*(dot(oc, oc) - r*r);

	if (d >= 0.0)
	{
		float t = (-b - sqrt(d) ) / a;
		if (t >= RayTMin() && t <= RayTCurrent() )
		{
			SphereAttr attr;
			attr.unused = float2(0.0, 0.0);
			ReportHit(t, 0u, attr);
		}
	}
}
