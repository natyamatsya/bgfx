// Slang port of examples/41-tess/terrain_common.sh -- the shared resources + LoD/subdivision
// helpers for the compute-driven terrain tessellation shaders. `import terrain_common;`.
//
// Modularity notes:
//   * The reusable resources (displacement/slope samplers, subd/atomic storage buffers) live
//     here as `public` declarations with explicit register(...) so every importer shares the
//     same bindings. Slang dead-strips the ones an importer does not touch, so an unused
//     sampler/buffer never leaks into that shader's reflection envelope.
//   * u_params is deliberately NOT declared here: it is a partially-used vec4[] whose active
//     extent differs per shader (glslang reflects the used extent), so a single shared size
//     would force the wrong UBO size. Each shader declares u_params itself and passes the
//     needed components (u_DmapFactor, u_LodFactor) to these helpers.
//   * Predefined uniforms (u_modelView, u_invView) are auto-injected by shaderc only into the
//     *entry-point* source, never into a preloaded library module, so computeLod takes them
//     as parameters -- the entry shader references u_modelView/u_invView and passes them in.
import bgfx_shader; // vec/mat aliases, texture2DLod, mtxGetColumn, mul
import isubd;       // findMSB_, isLeafKey, childrenKeys, isRootKey, isChildZeroKey, parentKey

// SAMPLER2D(u_DmapSampler, 0) -- displacement map.
public Texture2D    u_DmapSampler        : register(t0);
public SamplerState u_DmapSamplerSampler : register(s0);
// SAMPLER2D(u_SmapSampler, 1) -- slope map.
public Texture2D    u_SmapSampler        : register(t1);
public SamplerState u_SmapSamplerSampler : register(s1);

// BUFFER_RW(u_AtomicCounterBuffer, uint, 4); BUFFER_RW(u_SubdBufferOut, uint, 1)
public RWStructuredBuffer<uint> u_AtomicCounterBuffer : register(u4);
public RWStructuredBuffer<uint> u_SubdBufferOut       : register(u1);

// displacement map (_dmapFactor is the stock u_DmapFactor == u_params[0].x)
public float dmap(vec2 pos, float _dmapFactor)
{
	return (texture2DLod(u_DmapSampler, u_DmapSamplerSampler, pos * 0.5 + 0.5, 0.0).x) * _dmapFactor;
}

public float distanceToLod(float z, float lodFactor)
{
	// Note that we multiply the result by two because the triangles
	// edge lengths decreases by half every two subdivision steps.
	return -2.0 * log2(clamp(z * lodFactor, 0.0f, 1.0f));
}

// _modelView/_invView are the stock predefined u_modelView/u_invView; _dmapFactor/_lodFactor
// are u_params[0].x / u_params[0].y (see the header note on why they are parameters).
public float computeLod(vec3 c, mat4 _modelView, mat4 _invView, float _dmapFactor, float _lodFactor)
{
	//displace
	c.z += dmap(mtxGetColumn(_invView, 3).xy, _dmapFactor);

	vec3 cxf = mul(_modelView, vec4(c.x, c.y, c.z, 1)).xyz;
	float z = length(cxf);

	return distanceToLod(z, _lodFactor);
}

public float computeLod(in vec4 v[3], mat4 _modelView, mat4 _invView, float _dmapFactor, float _lodFactor)
{
	vec3 c = (v[1].xyz + v[2].xyz) / 2.0;
	return computeLod(c, _modelView, _invView, _dmapFactor, _lodFactor);
}

public float computeLod(in vec3 v[3], mat4 _modelView, mat4 _invView, float _dmapFactor, float _lodFactor)
{
	vec3 c = (v[1].xyz + v[2].xyz) / 2.0;
	return computeLod(c, _modelView, _invView, _dmapFactor, _lodFactor);
}

public void writeKey(uint primID, uint key)
{
	uint idx = 0;

	InterlockedAdd(u_AtomicCounterBuffer[0], 2u, idx); // atomicFetchAndAdd(u_AtomicCounterBuffer[0], 2, idx)

	u_SubdBufferOut[idx] = primID;
	u_SubdBufferOut[idx+1] = key;
}

public void updateSubdBuffer(
	  uint primID
	, uint key
	, uint targetLod
	, uint parentLod
	, bool isVisible
	)
{
	// extract subdivision level associated to the key
	uint keyLod = findMSB_(key);

	// update the key accordingly
	if (/* subdivide ? */ keyLod < targetLod && !isLeafKey(key) && isVisible)
	{
		uint children[2]; childrenKeys(key, children);

		writeKey(primID, children[0]);
		writeKey(primID, children[1]);
	}
	else if (/* keep ? */ keyLod < (parentLod + 1) && isVisible)
	{
		writeKey(primID, key);
	}
	else /* merge ? */
	{

		if (/* is root ? */isRootKey(key))
		{
			writeKey(primID, key);
		}

		else if (/* is zero child ? */isChildZeroKey(key)) {
			writeKey(primID, parentKey(key));
		}

	}
}

public void updateSubdBuffer(uint primID, uint key, uint targetLod, uint parentLod)
{
	updateSubdBuffer(primID, key, targetLod, parentLod, true);
}
