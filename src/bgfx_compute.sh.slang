// bgfx compute helpers for Slang -- mirrors the HLSL branch of src/bgfx_compute.sh.
// `import bgfx_compute;`.
import bgfx_shader; // ivec/uvec/vec aliases

// --- image load/store (generic over the texel type) ---
public void imageStore<T : ITexelElement>(RWTexture2D<T> _image, ivec2 _uv, T _value)       { _image[_uv]  = _value; }
public T    imageLoad<T : ITexelElement>(RWTexture2D<T> _image, ivec2 _uv)                  { return _image[_uv]; }
public void imageStore<T : ITexelElement>(RWTexture2DArray<T> _image, ivec3 _uvw, T _value) { _image[_uvw] = _value; }
public T    imageLoad<T : ITexelElement>(RWTexture2DArray<T> _image, ivec3 _uvw)            { return _image[_uvw]; }
public void imageStore<T : ITexelElement>(RWTexture3D<T> _image, ivec3 _uvw, T _value)      { _image[_uvw] = _value; }
public T    imageLoad<T : ITexelElement>(RWTexture3D<T> _image, ivec3 _uvw)                 { return _image[_uvw]; }

public ivec2 imageSize<T : ITexelElement>(RWTexture2D<T> _image)      { uvec2 r; _image.GetDimensions(r.x, r.y);      return ivec2(r); }
public ivec3 imageSize<T : ITexelElement>(RWTexture2DArray<T> _image) { uvec3 r; _image.GetDimensions(r.x, r.y, r.z); return ivec3(r); }
public ivec3 imageSize<T : ITexelElement>(RWTexture3D<T> _image)      { uvec3 r; _image.GetDimensions(r.x, r.y, r.z); return ivec3(r); }

// --- barriers ---
public void barrier()             { GroupMemoryBarrierWithGroupSync(); }
public void memoryBarrier()       { GroupMemoryBarrierWithGroupSync(); }
public void memoryBarrierShared() { GroupMemoryBarrierWithGroupSync(); }
public void memoryBarrierImage()  { GroupMemoryBarrierWithGroupSync(); }
public void memoryBarrierBuffer() { AllMemoryBarrierWithGroupSync(); }
public void groupMemoryBarrier()         { GroupMemoryBarrierWithGroupSync(); }
public void memoryBarrierAtomicCounter() { GroupMemoryBarrierWithGroupSync(); }

// Atomic add into a uint storage image (bgfx imageAtomicAdd); the image handle indexes the
// live UAV element, so the InterlockedAdd is a real atomic.
public void imageAtomicAdd(RWTexture2D<uint> _image, ivec2 _uv, uint _value) { InterlockedAdd(_image[_uv], _value); }

// --- read-only formatted images (bgfx IMAGE2D_RO/RW -> Texture2D via .Load, no []) ---
public T imageLoad<T : ITexelElement>(Texture2D<T> _image, ivec2 _uv)      { return _image.Load(ivec3(_uv, 0) ); }
public T imageLoad<T : ITexelElement>(Texture2DArray<T> _image, ivec3 _uvw) { return _image.Load(ivec4(_uvw, 0) ); }
public ivec2 imageSize<T : ITexelElement>(Texture2D<T> _image)      { uvec2 r; _image.GetDimensions(r.x, r.y);      return ivec2(r); }
public ivec3 imageSize<T : ITexelElement>(Texture2DArray<T> _image) { uvec3 r; _image.GetDimensions(r.x, r.y, r.z); return ivec3(r); }

// --- indirect args (write packed values into an RWStructuredBuffer<uvec4>, mirrors bgfx_compute.sh) ---
public void dispatchIndirect(RWStructuredBuffer<uvec4> _buffer, uint _offset, uint _numX, uint _numY, uint _numZ)
{
	_buffer[_offset*2+0] = uvec4(_numX, _numY, _numZ, 0u);
}
public void drawIndirect(RWStructuredBuffer<uvec4> _buffer, uint _offset, uint _numVertices, uint _numInstances, uint _startVertex, uint _startInstance)
{
	_buffer[_offset*2+0] = uvec4(_numVertices, _numInstances, _startVertex, _startInstance);
}
public void drawIndexedIndirect(RWStructuredBuffer<uvec4> _buffer, uint _offset, uint _numIndices, uint _numInstances, uint _startIndex, uint _startVertex, uint _startInstance)
{
	_buffer[_offset*2+0] = uvec4(_numIndices, _numInstances, _startIndex, _startVertex);
	_buffer[_offset*2+1] = uvec4(_startInstance, 0u, 0u, 0u);
}
