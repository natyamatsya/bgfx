// Slang port of examples/41-tess/cs_terrain_init.sc. Seeds the subd/atomic/indirect buffers
// once at startup. uniforms.sh is define-only -> its aliases are inlined here. The indirect
// helpers drawIndexedIndirect()/dispatchIndirect() come from bgfx_compute.
// atomicFetchAndExchange -> InterlockedExchange (a translation rule).
import bgfx_shader;  // uvec4 alias
import bgfx_compute; // drawIndexedIndirect, dispatchIndirect (atomics are a translation rule)

// bgfx predefined uniform: base folded into drawIndexedIndirect's start index (mirrors bgfx_compute.sh).
uniform vec4 bgfx_indirectArgBase;

// uniforms.sh
float4 u_params[2];
#define u_gpu_subd  int(u_params[1].x)
static const uint UPDATE_INDIRECT_VALUE_DIVIDE = 32u;

// BUFFER_WO(u_SubdBufferOut, uint, 1); BUFFER_RW(u_CulledSubdBuffer, uint, 2)
RWStructuredBuffer<uint>  u_SubdBufferOut     : register(u1);
RWStructuredBuffer<uint>  u_CulledSubdBuffer  : register(u2);
// BUFFER_RW(indirectBuffer, uvec4, 3); BUFFER_RW(atomicCounterBuffer, uint, 4)
RWStructuredBuffer<uint4> indirectBuffer      : register(u3);
RWStructuredBuffer<uint>  atomicCounterBuffer : register(u4);
// BUFFER_WO(u_SubdBufferIn, uint, 8)
RWStructuredBuffer<uint>  u_SubdBufferIn      : register(u8);

[shader("compute")]
[numthreads(1, 1, 1)]
void computeMain(uint3 gl_GlobalInvocationID : SV_DispatchThreadID)
{
	uint subd = uint(6 << (2 * u_gpu_subd - 1));

	if((2 * u_gpu_subd - 1) <= 0) {
		subd = 3u;
	}

	drawIndexedIndirect(indirectBuffer, 0u, subd, 0u, asuint(bgfx_indirectArgBase.x) + 0u, 0u, 0u);
	dispatchIndirect(indirectBuffer, 1u, 2u / UPDATE_INDIRECT_VALUE_DIVIDE + 1u, 1u, 1u);

	u_SubdBufferOut[0] = 0;
	u_SubdBufferOut[1] = 1;
	u_SubdBufferOut[2] = 1;
	u_SubdBufferOut[3] = 1;

	u_CulledSubdBuffer[0] = 0;
	u_CulledSubdBuffer[1] = 1;
	u_CulledSubdBuffer[2] = 1;
	u_CulledSubdBuffer[3] = 1;

	u_SubdBufferIn[0] = 0;
	u_SubdBufferIn[1] = 1;
	u_SubdBufferIn[2] = 1;
	u_SubdBufferIn[3] = 1;

	uint tmp;

	InterlockedExchange(atomicCounterBuffer[0], 0, tmp);
	InterlockedExchange(atomicCounterBuffer[1], 0, tmp);
	InterlockedExchange(atomicCounterBuffer[2], 2, tmp);
}
