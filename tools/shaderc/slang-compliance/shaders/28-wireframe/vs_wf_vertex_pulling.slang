// 1-to-1 Slang port of examples/28-wireframe vs_wf_vertex_pulling.sc.
// Vertex-pulling VS: no vertex attributes, reads geometry from storage buffers indexed by
// gl_VertexID (-> SV_VertexID). BUFFER_RO(name, T, N) -> StructuredBuffer<T> at register tN.
// Predefined u_modelViewProj / u_viewRect are auto-declared. u_params is the custom array
// from uniforms.sh (declared vec4[3]); this VS reads u_wfColor/u_wfOpacity (u_params[1]) and
// u_wfThickness/u_wfStride (u_params[2]), so the active extent is the full 3 -- no padding.
// getIndex/getPosition are defined inline in the .sc body, so they stay inline. mix comes
// from bgfx_shader_glsl_compat.
import bgfx_shader;
import bgfx_shader_glsl_compat;

StructuredBuffer<float> positions : register(t0);
StructuredBuffer<uint>  indices   : register(t1);

float4 u_params[3];
// u_wfColor      = u_params[1].xyz
// u_wfOpacity    = u_params[1].w
// u_wfThickness  = u_params[2].y
// u_wfStride     = u_params[2].z

uint getIndex(uint i)
{
	uint idx32 = indices[i / 2u];
	if (i % 2u == 0u)
	{
		return idx32 & 0xFFFFu;
	}
	else
	{
		return idx32 >> 16u;
	}
}

vec3 getPosition(uint index)
{
	uint strideFloats = uint(u_params[2].z);
	uint offset = index * strideFloats;
	return vec3(
		positions[offset + 0u],
		positions[offset + 1u],
		positions[offset + 2u]
	);
}

#define NEAR_EPSILON 0.001
#define LENGTH_EPSILON 0.0001

struct V2F
{
	vec4 pos     : SV_Position;
	vec4 v_color : COLOR0;
};

// gl_VertexID lives inside a VSInput struct so the slang envelope reflects the same single
// (non-bgfx-attribute) live input the stock glslang path reports for gl_VertexID -- an
// UINT16_MAX attribute id. A bare entry-point parameter would not be counted.
struct VSInput
{
	uint gl_VertexID : SV_VertexID;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	uint gl_VertexID = input.gl_VertexID;
	uint lineIndex = gl_VertexID / 6u;
	uint localVertex = gl_VertexID % 6u;

	uint edgeIndex = lineIndex % 3u;
	uint triFirstIndex = lineIndex - edgeIndex;

	uint idx0_loc = triFirstIndex + edgeIndex;
	uint idx1_loc = triFirstIndex + ((edgeIndex + 1u) % 3u);

	uint vertexIndex0 = getIndex(idx0_loc);
	uint vertexIndex1 = getIndex(idx1_loc);

	vec3 p0 = getPosition(vertexIndex0);
	vec3 p1 = getPosition(vertexIndex1);

	vec4 p0_NDC = mul(u_modelViewProj, vec4(p0, 1.0));
	vec4 p1_NDC = mul(u_modelViewProj, vec4(p1, 1.0));

	vec4 c0 = vec4(u_params[1].xyz, u_params[1].w);
	vec4 c1 = vec4(u_params[1].xyz, u_params[1].w);

	vec4 clippedP0 = p0_NDC;
	vec4 clippedP1 = p1_NDC;
	vec4 clippedColor0 = c0;
	vec4 clippedColor1 = c1;

	if (p0_NDC.w < NEAR_EPSILON)
	{
		float t = (NEAR_EPSILON - p0_NDC.w) / (p1_NDC.w - p0_NDC.w);
		clippedP0 = mix(p0_NDC, p1_NDC, t);
		clippedColor0 = mix(c0, c1, t);
	}
	if (p1_NDC.w < NEAR_EPSILON)
	{
		float t = (NEAR_EPSILON - p1_NDC.w) / (p0_NDC.w - p1_NDC.w);
		clippedP1 = mix(p1_NDC, p0_NDC, t);
		clippedColor1 = mix(c1, c0, t);
	}

	const vec2 offsets[6] =
	{
		vec2(-1.0, -1.0), vec2(-1.0,  1.0), vec2( 1.0, -1.0),
		vec2( 1.0, -1.0), vec2(-1.0,  1.0), vec2( 1.0,  1.0)
	};
	vec2 offset = offsets[localVertex];
	vec2 uv = offset * 0.5 + 0.5;

	vec4 p = mix(clippedP0, clippedP1, uv.x);
	vec4 color = mix(clippedColor0, clippedColor1, uv.x);

	vec2 ndp0 = clippedP0.xy / clippedP0.w;
	vec2 ndp1 = clippedP1.xy / clippedP1.w;
	vec2 screenDir = ndp1 - ndp0;
	float screenDirLen = length(screenDir);

	if (screenDirLen > LENGTH_EPSILON)
	{
		vec2 T = screenDir / screenDirLen;
		vec2 N = vec2(-T.y, T.x);

		float pixelsToNDCX = 2.0 / u_viewRect.z;
		float pixelsToNDCY = 2.0 / u_viewRect.w;

		float side = 2.0 * uv.y - 1.0;
		vec2 offsetNDC = N * (0.5 * u_params[2].y) * side * vec2(pixelsToNDCX, pixelsToNDCY);

		p.xy = p.xy + (offsetNDC * p.w);
	}

	V2F output;
	output.v_color = color;
	output.pos = p;
	return output;
}
