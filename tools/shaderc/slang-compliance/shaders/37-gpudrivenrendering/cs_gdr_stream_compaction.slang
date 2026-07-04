// Slang port of examples/37-gpudrivenrendering cs_gdr_stream_compaction.sc.
// Parallel prefix-sum (Blelloch scan, "Parallel Prefix Sum (Scan) with CUDA", Mark Harris)
// over the per-instance visibility predicates to compact the surviving instances into a
// dense output buffer, then thread 0 packs one drawIndexedIndirect command per drawcall.
import bgfx_compute;
import bgfx_shader;

// bgfx predefined uniform: base folded into drawIndexedIndirect's start index (mirrors bgfx_compute.sh).
uniform vec4 bgfx_indirectArgBase;

//the per drawcall data that is constant (noof indices and offsets to vertex/index buffers)
StructuredBuffer<uint>     drawcallConstData     : register(t0); // BUFFER_RO(drawcallConstData, uint, 0)
//instance data for all instances (pre culling)
StructuredBuffer<float4>   instanceDataIn        : register(t1); // BUFFER_RO(instanceDataIn, vec4, 1)
//per instance visibility (output of culling pass)
StructuredBuffer<bool>     instancePredicates    : register(t2); // BUFFER_RO(instancePredicates, bool, 2)

//how many instances per drawcall
RWStructuredBuffer<uint>   drawcallInstanceCount : register(u3); // BUFFER_RW(drawcallInstanceCount, uint, 3)
//drawcall data that will drive drawIndirect
RWStructuredBuffer<uint4>  drawcallData          : register(u4); // BUFFER_RW(drawcallData, uvec4, 4)
//culled instance data
RWStructuredBuffer<float4> instanceDataOut       : register(u5); // BUFFER_WO(instanceDataOut, vec4, 5)

uniform float4 u_cullingConfig;

// Based on Parallel Prefix Sum (Scan) with CUDA by Mark Harris
groupshared uint temp[2048];

[shader("compute")]
[numthreads(1024, 1, 1)]
void computeMain(uint3 dispatchThreadId : SV_DispatchThreadID)
{
	uint tID = dispatchThreadId.x;
	int NoofInstancesPowOf2 = int(u_cullingConfig.y);
	int NoofDrawcalls = int(u_cullingConfig.w);

	int offset = 1;
	bool predicate = instancePredicates[2 * tID];
	temp[2 * tID] = uint(predicate ? 1 : 0);

	predicate = instancePredicates[2 * tID + 1];
	temp[2 * tID + 1] = uint(predicate ? 1 : 0);

	int d;

	//perform reduction
	for (d = NoofInstancesPowOf2 >> 1; d > 0; d >>= 1)
	{
		barrier();

		if (tID < uint(d) )
		{
			int ai = int(offset * (2 * tID + 1) - 1);
			int bi = int(offset * (2 * tID + 2) - 1);
			temp[bi] += temp[ai];
		}

		offset *= 2;
	}

	// clear the last element
	if (tID == 0)
	{
		temp[NoofInstancesPowOf2 - 1] = 0;
	}

	// perform downsweep and build scan
	for ( d = 1; d < NoofInstancesPowOf2; d *= 2)
	{
		offset >>= 1;

		barrier();

		if (tID < uint(d) )
		{
			int ai = int(offset * (2 * tID + 1) - 1);
			int bi = int(offset * (2 * tID + 2) - 1);
			int t  = int(temp[ai]);
			temp[ai] = temp[bi];
			temp[bi] += uint(t);
		}
	}

	barrier();

	int index = int(2 * tID);

	// scatter results
	predicate = instancePredicates[index];
	if (predicate)
	{
		instanceDataOut[4 * temp[index]    ] = instanceDataIn[4 * index    ];
		instanceDataOut[4 * temp[index] + 1] = instanceDataIn[4 * index + 1];
		instanceDataOut[4 * temp[index] + 2] = instanceDataIn[4 * index + 2];
		instanceDataOut[4 * temp[index] + 3] = instanceDataIn[4 * index + 3];
	}

	index = int(2 * tID + 1);

	predicate = instancePredicates[index];
	if (predicate)
	{
		instanceDataOut[4 * temp[index]    ] = instanceDataIn[4 * index    ];
		instanceDataOut[4 * temp[index] + 1] = instanceDataIn[4 * index + 1];
		instanceDataOut[4 * temp[index] + 2] = instanceDataIn[4 * index + 2];
		instanceDataOut[4 * temp[index] + 3] = instanceDataIn[4 * index + 3];
	}

	if (tID == 0)
	{
		uint startInstance = 0;

		//copy data to indirect buffer, could possible be done in a different compute shader
		for (int k = 0; k < NoofDrawcalls; k++)
		{
			drawIndexedIndirect(
				drawcallData,
				k,
				drawcallConstData[ k * 3 ], 			//number of indices
				drawcallInstanceCount[k], 				//number of instances
				asuint(bgfx_indirectArgBase.x) + drawcallConstData[ k * 3 + 1 ],			//offset into the index buffer
				drawcallConstData[ k * 3 + 2 ],			//offset into the vertex buffer
				startInstance							//offset into the instance buffer
				);

			startInstance += drawcallInstanceCount[k];

			drawcallInstanceCount[k] = 0;
		}
	}
}
