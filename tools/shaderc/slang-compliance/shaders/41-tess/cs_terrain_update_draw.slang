// Slang port of examples/41-tess/cs_terrain_update_draw.sc. Patches the indexed-indirect draw
// args with the culled instance count. uniforms.sh is define-only (inlined). drawIndexedIndirect
// comes from bgfx_compute.
import bgfx_shader;  // uvec4 alias
import bgfx_compute; // drawIndexedIndirect

// bgfx predefined uniform: base folded into drawIndexedIndirect's start index (mirrors bgfx_compute.sh).
uniform vec4 bgfx_indirectArgBase;

// uniforms.sh
float4 u_params[2];
#define u_gpu_subd int(u_params[1].x)

// BUFFER_RW(indirectBuffer, uvec4, 3); BUFFER_RW(atomicCounterBuffer, uint, 4)
RWStructuredBuffer<uint4> indirectBuffer      : register(u3);
RWStructuredBuffer<uint>  atomicCounterBuffer : register(u4);

[shader("compute")]
[numthreads(1, 1, 1)]
void computeMain(uint3 gl_GlobalInvocationID : SV_DispatchThreadID)
{
	uint counter = atomicCounterBuffer[1];

	uint subd = uint(6 << (2 * u_gpu_subd - 1));

	if((2 * u_gpu_subd - 1) <= 0) {
		subd = 3u;
	}

	drawIndexedIndirect(indirectBuffer, 0, subd, counter / 2, asuint(bgfx_indirectArgBase.x) + 0u, 0u, 0u);
}
