// Slang port of examples/41-tess/vs_terrain_render.sc. Vertex-pulls one visible subdivision
// key per instance (gl_InstanceID -> SV_InstanceID), subdivides + barycentric-interpolates the
// sub-triangle vertex, displaces it, and projects it. Shared helpers come from the co-located
// libraries (terrain_common: dmap; isubd: subd/berp). uniforms.sh is define-only (inlined).
import bgfx_shader;    // vec/mat aliases, mul
import terrain_common; // u_DmapSampler, dmap
import isubd;          // subd, berp

// uniforms.sh
float4 u_params[1];
#define u_DmapFactor u_params[0].x

// BUFFER_RO(u_CulledSubdBuffer, uint, 2); BUFFER_RO(u_VertexBuffer, vec4, 3); BUFFER_RO(u_IndexBuffer, uint, 4)
StructuredBuffer<uint> u_CulledSubdBuffer : register(t2);
StructuredBuffer<vec4> u_VertexBuffer     : register(t3);
StructuredBuffer<uint> u_IndexBuffer      : register(t4);

struct VSInput
{
	vec2 a_texcoord0  : TEXCOORD0;
	uint gl_InstanceID : SV_InstanceID;
};

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_texcoord0 : TEXCOORD0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	// get threadID (each key is associated to a thread)
	int threadID = int(input.gl_InstanceID);

	// get coarse triangle associated to the key
	uint primID = u_CulledSubdBuffer[threadID*2];

	vec4 v_in[3];

	v_in[0] = u_VertexBuffer[u_IndexBuffer[primID * 3    ]];
	v_in[1] = u_VertexBuffer[u_IndexBuffer[primID * 3 + 1]];
	v_in[2] = u_VertexBuffer[u_IndexBuffer[primID * 3 + 2]];

	// compute sub-triangle associated to the key
	uint key = u_CulledSubdBuffer[threadID*2+1];

	vec4 v[3];

	subd(key, v_in, v);

	// compute vertex location
	vec4 finalVertex = berp(v, input.a_texcoord0);

	finalVertex.z += dmap(finalVertex.xy, u_DmapFactor);

	V2F output;
	output.v_texcoord0 = finalVertex.xy * 0.5 + 0.5;

	output.pos = mul(u_modelViewProj, finalVertex);
	return output;
}
