// Ray-generation stage of the RT-pipeline render stage: shoots the deterministic
// pixel-centre primary ray (same camera as every other pass, from cornellbox.sh) and
// writes the shaded payload straight to the display image -- byte-comparable with the
// "Simple RT" ray-query stage, which computes the same image on the compute pipeline.
import bgfx_shader;
import bgfx_compute;
import "cornellbox.sh";

uniform RaytracingAccelerationStructure scene : register(t0); // stage 0
RWTexture2D<float4> s_target : register(u1);                  // stage 1

// x = frame index, y = unused, z = box rotation angle, w = unused.
uniform float4 u_params;

[shader("raygeneration")]
void rayGenMain()
{
	uint2 px = DispatchRaysIndex().xy;
	float2 res = float2(DispatchRaysDimensions().xy);

	RayDesc rd;
	rd.Origin    = kEye;
	rd.Direction = primaryRay(float2(px), float2(0.5, 0.5), res);
	rd.TMin      = 1e-3;
	rd.TMax      = 1000.0;

	RtPipePayload p;
	p.color = float3(0, 0, 0);
	p.angle = u_params.z;
	TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 0, 0, rd, p);

	imageStore(s_target, ivec2(px), float4(tonemap(p.color), 1.0) );
}
