// Slang port of examples/43-denoise normal_encoding.sh -- the example-local normal
// encode/decode helpers shared by the gbuffer/deferred-combine/spatial/temporal passes.
// `import normal_encoding;`. These are pure functions (no uniforms/samplers), so the
// reflection envelope is unchanged by importing them.
//
// From "A Survey of Efficient Representations for Independent Unit Vectors"
// http://jcgt.org/published/0003/02/01/paper.pdf
import bgfx_shader;

// NE_USE_OCTAHEDRAL_REPRESENTATION == 0 (default), so NormalEncode/NormalDecode use the
// plain remap branch below. The octahedral helpers are ported faithfully but stay unused.

// Convert an oct24 (2x12bit normal) to an rgb8 value for storing in texture
public vec3 snorm12x2_to_unorm8x3(vec2 f) {

	f        = clamp(f, -1.0, 1.0);//min(max(f, vec2(-1.0)), vec2(1.0));
	vec2   u = floor(f * 2047.0 + 2047.5);
	float  t = floor(u.y / 256.0);

	// "This code assumes that rounding will occur during storage."
	// -- Not certain but this appears to mainly apply to the x channel.
	//    From paper: x = u.x / 16.0 - 0.5
	//    Instead round by +0.5 and floor.
	return vec3(floor(u.x / 16.0), fract(u.x / 16.0) * 256.0 + t, u.y - t * 256.0) / 255.0;
}

// Unpack oct24 (2x12bit normal) from an rgb8 value stored in texture (normal spec)
public vec2 unorm8x3_to_snorm12x2(vec3 u) {

	u *= 255.0;
	u.y *= (1.0 / 16.0);
	vec2 s = vec2(u.x * 16.0 + floor(u.y), fract(u.y) * (16.0 * 256.0) + u.z);

	s = s * (1.0 / 2047.0) - 1.0;
	return min(max(s, -1.0), 1.0);
}

// Built in sign test could return 0, don't want that
public vec2 signNotZero(vec2 v) {
	return vec2((v.x >= 0.0) ? 1.0 : -1.0, (v.y >= 0.0) ? 1.0 : -1.0);
}

// Assume normalized input. Output is (-1, 1) for each component
public vec2 float32x3_to_oct(vec3 v) {

	// Project the sphere onto the octahedron, and then onto the xy plane
	vec2 p = v.xy * (1.0 / (abs(v.x) + abs(v.y) + abs(v.z)));

	// Reflect the folds of the lower hemisphere over the diagonals
	return (v.z <= 0.0) ? ((1.0 - abs(p.yx)) * signNotZero(p)) : p;
}

// Get a float3 normal from an oct representation
public vec3 oct_to_float32x3(vec2 e) {
	vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
	if (v.z < 0.0) {
		v.xy = (1.0 - abs(v.yx)) * signNotZero(v.xy);
	}

	return normalize(v);
}

public vec3 SignedNormalEncodeToOct(vec3 normal) {

	return snorm12x2_to_unorm8x3(float32x3_to_oct(normal));
}

public vec3 SignedNormalDecodeFromOct(vec3 normal) {

	return oct_to_float32x3(unorm8x3_to_snorm12x2(normal));
}

public vec3 NormalEncode(vec3 normal)
{
	return normal * 0.5 + 0.5;
}

public vec3 NormalDecode(vec3 normal)
{
	return normal * 2.0 - 1.0;
}
