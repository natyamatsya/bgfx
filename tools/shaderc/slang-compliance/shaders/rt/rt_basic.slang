// Basic ray tracing module exercising all six RT shader stages the Slang front-end
// supports (raygeneration / intersection / anyhit / closesthit / miss / callable).
// There is no stock .sc equivalent -- bgfx has no RT front-end -- so rt_stages.py
// validates this by self-check (valid SPIR-V + expected stage + reflected resources)
// rather than by parity against the stock compiler.

struct Payload  { float3 color; };
struct Attr     { float2 bary;  };
struct CallData { float3 value; };

uniform RaytracingAccelerationStructure scene;
uniform RWTexture2D<float4> output;

[shader("raygeneration")]
void rgenMain()
{
	uint2 idx = DispatchRaysIndex().xy;

	RayDesc ray;
	ray.Origin    = float3(idx, 0);
	ray.Direction = float3(0, 0, 1);
	ray.TMin      = 0.0;
	ray.TMax      = 1000.0;

	Payload payload = { float3(0, 0, 0) };
	TraceRay(scene, RAY_FLAG_NONE, 0xff, 0, 0, 0, ray, payload);

	output[idx] = float4(payload.color, 1.0);
}

[shader("intersection")]
void rintMain()
{
	Attr attr = { float2(0.5, 0.5) };
	ReportHit(1.0, 0u, attr);
}

[shader("anyhit")]
void rahitMain(inout Payload payload, in Attr attr)
{
	payload.color = float3(attr.bary, 0.0);
}

[shader("closesthit")]
void rchitMain(inout Payload payload, in BuiltInTriangleIntersectionAttributes attr)
{
	payload.color = float3(attr.barycentrics, 1.0);
}

[shader("miss")]
void rmissMain(inout Payload payload)
{
	payload.color = float3(0.1, 0.2, 0.3);
}

[shader("callable")]
void rcallMain(inout CallData data)
{
	data.value = float3(1.0, 0.0, 0.0);
}
