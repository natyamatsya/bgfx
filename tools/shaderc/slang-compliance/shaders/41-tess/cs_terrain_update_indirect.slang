// Slang port of examples/41-tess/cs_terrain_update_indirect.sc. Consumes the atomic counters
// and patches the dispatch-indirect args for the next LoD pass. uniforms.sh is define-only
// (only UPDATE_INDIRECT_VALUE_DIVIDE is used). atomicFetchAndExchange -> InterlockedExchange
// (a translation rule); dispatchIndirect comes from bgfx_compute.
import bgfx_shader;  // uvec4 alias
import bgfx_compute; // dispatchIndirect (atomics are a translation rule)

// uniforms.sh
static const uint UPDATE_INDIRECT_VALUE_DIVIDE = 32u;

// BUFFER_RW(indirectBuffer, uvec4, 3); BUFFER_RW(atomicCounterBuffer, uint, 4)
RWStructuredBuffer<uint4> indirectBuffer      : register(u3);
RWStructuredBuffer<uint>  atomicCounterBuffer : register(u4);

[shader("compute")]
[numthreads(1, 1, 1)]
void computeMain(uint3 gl_GlobalInvocationID : SV_DispatchThreadID)
{
	uint counter;
	uint counter2;

	InterlockedExchange(atomicCounterBuffer[0], 0u, counter);
	InterlockedExchange(atomicCounterBuffer[1], 0u, counter2);

	uint cnt = (counter / 2u) / UPDATE_INDIRECT_VALUE_DIVIDE + 1u;

	uint tmp;

	InterlockedExchange(atomicCounterBuffer[2], (counter / 2), tmp);

	dispatchIndirect(indirectBuffer, 1u, cnt, 1u, 1u);
}
