////////////////////////////////////////////////////////////////////////////////
// Implicit Subdivision Shader for Terrain Rendering
//
// Slang port of examples/41-tess/cs_terrain_lod.sc. This is the distance-based LoD pass: each
// thread takes one subdivision key, subdivides its coarse triangle, decides subdivide/keep/
// merge, and frustum-culls the result into the visible buffer. The shared resources + helpers
// come from the co-located libraries (terrain_common / isubd / fcull); uniforms.sh is
// define-only and inlined. atomicFetchAndAdd -> InterlockedAdd (a translation rule).
import bgfx_shader;     // vec/mat aliases
import bgfx_compute;    // (compute preamble; atomics are a translation rule, see above)
import terrain_common;  // u_DmapSampler, u_AtomicCounterBuffer, u_SubdBufferOut, computeLod, updateSubdBuffer
import isubd;           // subd, findMSB_
import fcull;           // frustumCullingTest

// uniforms.sh
float4 u_params[1];
#define u_DmapFactor u_params[0].x
#define u_LodFactor  u_params[0].y
#define u_cull       u_params[0].z
#define u_freeze     u_params[0].w
// COMPUTE_THREAD_COUNT == 32u

// BUFFER_RO(u_SubdBufferIn, uint, 8); BUFFER_RW(u_CulledSubdBuffer, uint, 2)
StructuredBuffer<uint>   u_SubdBufferIn     : register(t8);
RWStructuredBuffer<uint> u_CulledSubdBuffer : register(u2);
// BUFFER_RO(u_VertexBuffer, vec4, 6); BUFFER_RO(u_IndexBuffer, uint, 7)
StructuredBuffer<vec4>   u_VertexBuffer     : register(t6);
StructuredBuffer<uint>   u_IndexBuffer      : register(t7);

/**
 * Compute LoD Shader
 *
 * This compute shader is responsible for updating the subdivision
 * buffer and visible buffer that will be sent to the rasterizer.
 */
[shader("compute")]
[numthreads(32, 1, 1)]
void computeMain(uint3 gl_GlobalInvocationID : SV_DispatchThreadID)
{
	// get threadID (each key is associated to a thread)
	uint threadID = gl_GlobalInvocationID.x;

	if (threadID >= u_AtomicCounterBuffer[2])
	{
		return;
	}

	// get coarse triangle associated to the key
	uint primID = u_SubdBufferIn[threadID*2];

	vec4 v_in[3];
	v_in[0] = u_VertexBuffer[u_IndexBuffer[primID * 3    ]];
	v_in[1] = u_VertexBuffer[u_IndexBuffer[primID * 3 + 1]];
	v_in[2] = u_VertexBuffer[u_IndexBuffer[primID * 3 + 2]];

	// compute distance-based LOD
	uint key = u_SubdBufferIn[threadID*2+1];

	vec4 v[3];
	vec4 vp[3];

	subd(key, v_in, v, vp);

	uint targetLod; uint parentLod;

	if (u_freeze == 0)
	{
		targetLod = uint(computeLod(v,  u_modelView, u_invView, u_DmapFactor, u_LodFactor));
		parentLod = uint(computeLod(vp, u_modelView, u_invView, u_DmapFactor, u_LodFactor));
	}
	else
	{
		targetLod = parentLod = findMSB_(key);
	}

	updateSubdBuffer(primID, key, targetLod, parentLod);

	// Cull invisible nodes
	mat4 mvp = u_modelViewProj;
	vec4 bmin = min(min(v[0], v[1]), v[2]);
	vec4 bmax = max(max(v[0], v[1]), v[2]);

	// account for displacement in bound computations
	bmin.z = 0;
	bmax.z = u_DmapFactor;

	// update CulledSubdBuffer
	if (u_cull == 0
	||  frustumCullingTest(mvp, bmin.xyz, bmax.xyz) )
	{
		// write key
		uint idx = 0;
		InterlockedAdd(u_AtomicCounterBuffer[1], 2u, idx); // atomicFetchAndAdd(u_AtomicCounterBuffer[1], 2, idx)
		u_CulledSubdBuffer[idx] = primID;
		u_CulledSubdBuffer[idx+1] = key;
	}
}
