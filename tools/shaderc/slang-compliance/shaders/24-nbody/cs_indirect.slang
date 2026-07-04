// 1-to-1 Slang port of examples/24-nbody cs_indirect.sc.
// Fills the indirect-args buffer that drives the update dispatch + the instanced draw.
//
// The stock shader uses the drawIndexedIndirect()/dispatchIndirect() macros from
// bgfx_compute.sh; those are now provided by src/bgfx_compute.sh.slang as library functions
// that write the exact same uvec4 stores, so we import and call them here.
import bgfx_shader;
import bgfx_compute;
import bgfx_shader_glsl_compat;

// bgfx predefined uniform: base folded into drawIndexedIndirect's start index (mirrors bgfx_compute.sh).
uniform vec4 bgfx_indirectArgBase;

// uniforms.sh: uniform vec4 u_params[3]; cs_indirect only reads u_params[0], so glslang
// reflects the array at the active extent [1] while still reserving the declared [3] in
// $Globals -- the reserved tail (2*vec4 = 32 bytes) is reproduced by an unused pad member.
struct ParamsTailPad { vec4 _unused[2]; };
float4 u_params[1];
ParamsTailPad _paramsTailPad;

// #define u_dispatchSize floatBitsToUint(u_params[0].y); #define threadGroupUpdateSize 512
// BUFFER_WO(indirectBuffer, uvec4, 0)
RWStructuredBuffer<uvec4> indirectBuffer : register(u0);

[shader("compute")]
[numthreads(1, 1, 1)]
void computeMain(uint3 gl_GlobalInvocationID : SV_DispatchThreadID)
{
	uint u_dispatchSize = floatBitsToUint(u_params[0].y);

	drawIndexedIndirect(indirectBuffer, 0, 6u, u_dispatchSize * 512u, floatBitsToUint(bgfx_indirectArgBase.x) + 0u, 0u, 0u);

	dispatchIndirect(indirectBuffer, 1, u_dispatchSize, 1u, 1u);
}
