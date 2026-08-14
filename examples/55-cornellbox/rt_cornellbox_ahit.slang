// Any-hit stage of the RT-pipeline render stage. Its only job is to make the shadow ray
// agree with the ray-query tracer's occluded(), which skips emissive geometry ("the light
// itself does not shadow"). The closest-hit stage's shadow ray is traced with
// ACCEPT_FIRST_HIT_AND_END_SEARCH | SKIP_CLOSEST_HIT_SHADER, so it never gets to inspect a
// material -- any hit at all would mark the surface shadowed, and points whose shadow ray
// clips the light's own quad came out shadowed here but lit in the ray-query path.
// Rejecting emissive hits here restores the match.
//
// bgfx builds BLAS geometry opaque, so this stage runs only because the shadow ray adds
// RAY_FLAG_FORCE_NON_OPAQUE. The primary ray keeps RAY_FLAG_NONE and therefore still skips
// any-hit entirely, even though both rays share hit group 0.
import bgfx_shader;
import bgfx_compute;
import "cornellbox.sh";

struct Material
{
	float4 albedo;   // xyz
	float4 emission; // xyz
	float4 normal;   // xyz, inward-facing, in BLAS-local space
};
RWStructuredBuffer<Material> materials : register(u3); // stage 3, same table as closest-hit

[shader("anyhit")]
void anyHitMain(inout RtShadowPayload p, in BuiltInTriangleIntersectionAttributes attribs)
{
	uint matIdx = InstanceIndex()*12 + PrimitiveIndex();
	float3 emission = materials[matIdx].emission.xyz;

	if (dot(emission, emission) > 0.0)
	{
		// Emitters do not occlude: let traversal continue past the light.
		IgnoreHit();
	}
}
