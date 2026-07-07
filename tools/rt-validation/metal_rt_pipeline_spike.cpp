// Metal RT-pipeline SPIKE: proves, on-device and standalone (raw metal-cpp, no bgfx),
// that bgfx's ray-tracing PIPELINE model (createRtProgram: raygen/miss/closest-hit/
// any-hit/intersection/callable + an SBT) maps onto Metal's canonical equivalents:
//
//   raygen                -> the compute kernel (dispatch dims are rays, like bgfx)
//   miss/closest-hit/
//   callable              -> [[visible]] functions in a MTLVisibleFunctionTable,
//                            selected by a small "software SBT" buffer of table indices
//                            (bgfx's SBT regions hold indices instead of GPU handles)
//   intersection/any-hit  -> [[intersection(...)]] functions in a
//                            MTLIntersectionFunctionTable, consumed by the intersector
//                            natively (per-geometry intersectionFunctionTableOffset)
//
// Phase A: triangle TLAS; the kernel routes hit->chitFn / miss->missFn through the
//          visible-function table and chitFn validates the intersection distance.
// Phase B: procedural sphere in an AABB BLAS; a bounding-box intersection function
//          reports the analytic entry point; same visible-function routing on top.
//
// Both phases write 0.75 only when everything works (0.25 = routed to miss,
// 0.5 = hit with a wrong distance) -- the same additive-value discipline as the
// Vulkan rt_pipeline_smoke phases.
//
// The missing piece for production is CODEGEN: as of Slang 2025.23 the Metal target
// rejects ray-tracing stages ("not available in 'raygen' stage for 'metal'"), and
// SPIRV-Cross has no MSL path for them either. This spike therefore hand-writes the
// MSL the future compiler would emit; see METAL_RT_PIPELINE.md.
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#define NS_PRIVATE_IMPLEMENTATION
#include <metal-cpp/metal.hpp>
#include <cstdio>
#include <cstring>
#include <vector>

static const char* kMsl = R"MSL(
#include <metal_stdlib>
using namespace metal;
using namespace metal::raytracing;

// ---- "miss shader" / "closest-hit shader" as visible functions (the SBT entries) ----
[[visible]] float missFn(float unused)
{
	return 0.25;
}

[[visible]] float chitFn(float distance)
{
	// 0.75 only when the intersection distance matches the analytic 4.2 (both the
	// triangle at z=5 traced from z=0.8... no: triangle hit t=5? see host: triangle at
	// z=4.2 for phase A so both phases validate the same distance).
	return (abs(distance - 4.2) < 0.01) ? 0.75 : 0.5;
}

// ---- "intersection shader" for the procedural sphere (phase B) ----
struct BoxResult
{
	bool  accept   [[accept_intersection]];
	float distance [[distance]];
};

[[intersection(bounding_box, instancing)]]
BoxResult sphereIsect(float3 origin        [[origin]]
	, float3               direction        [[direction]]
	, float                minDistance      [[min_distance]]
	, float                maxDistance      [[max_distance]])
{
	const float3 c = float3(0.0, 0.0, 5.0);
	const float  r = 0.8;

	float3 oc = origin - c;
	float a = dot(direction, direction);
	float b = dot(oc, direction);
	float d = b*b - a*(dot(oc, oc) - r*r);

	BoxResult result;
	result.accept = false;
	result.distance = 0.0;
	if (d >= 0.0)
	{
		float t = (-b - sqrt(d)) / a;
		if (t >= minDistance && t <= maxDistance)
		{
			result.accept = true;
			result.distance = t;
		}
	}
	return result;
}

// ---- "raygen shader" phase A: triangle path, visible-function SBT routing ----
using handler_t = float(float);

kernel void rgTriangle(instance_acceleration_structure as [[buffer(0)]]
	, visible_function_table<handler_t> fns              [[buffer(1)]]
	, constant uint2&                   sbt              [[buffer(2)]]
	, texture2d<float, access::write>   target           [[texture(0)]]
	, uint2                             tid              [[thread_position_in_grid]])
{
	ray r;
	r.origin = float3(0.0, 0.0, 0.0);
	r.direction = float3(0.0, 0.0, 1.0);
	r.min_distance = 0.0;
	r.max_distance = 100.0;

	intersector<triangle_data, instancing> trace;
	trace.assume_geometry_type(geometry_type::triangle);
	intersection_result<triangle_data, instancing> hit = trace.intersect(r, as, 0xffu);

	float value = (hit.type == intersection_type::triangle)
		? fns[sbt.y](hit.distance)  // "closest hit"
		: fns[sbt.x](0.0);          // "miss"

	target.write(float4(value, value, value, 1.0), tid);
}

// ---- "raygen shader" phase B: procedural path via the intersection function table ----
kernel void rgProcedural(instance_acceleration_structure as       [[buffer(0)]]
	, visible_function_table<handler_t>                  fns      [[buffer(1)]]
	, constant uint2&                                    sbt      [[buffer(2)]]
	, intersection_function_table<instancing>            isectFns [[buffer(3)]]
	, texture2d<float, access::write>                    target   [[texture(0)]]
	, uint2                                              tid      [[thread_position_in_grid]])
{
	ray r;
	r.origin = float3(0.0, 0.0, 0.0);
	r.direction = float3(0.0, 0.0, 1.0);
	r.min_distance = 0.0;
	r.max_distance = 100.0;

	intersector<instancing> trace;
	intersection_result<instancing> hit = trace.intersect(r, as, 0xffu, isectFns);

	float value = (hit.type == intersection_type::bounding_box)
		? fns[sbt.y](hit.distance)
		: fns[sbt.x](0.0);

	target.write(float4(value, value, value, 1.0), tid);
}
)MSL";

static MTL::AccelerationStructure* buildAs(MTL::Device* dev, MTL::CommandQueue* queue, MTL::AccelerationStructureDescriptor* desc)
{
	MTL::AccelerationStructureSizes sizes = dev->accelerationStructureSizes(desc);
	MTL::AccelerationStructure* as = dev->newAccelerationStructure(sizes.accelerationStructureSize);
	MTL::Buffer* scratch = dev->newBuffer(sizes.buildScratchBufferSize, MTL::ResourceStorageModePrivate);

	MTL::CommandBuffer* cmd = queue->commandBuffer();
	MTL::AccelerationStructureCommandEncoder* enc = cmd->accelerationStructureCommandEncoder();
	enc->buildAccelerationStructure(as, desc, scratch, 0);
	enc->endEncoding();
	cmd->commit();
	cmd->waitUntilCompleted();
	scratch->release();
	return as;
}

static MTL::AccelerationStructure* buildTlas(MTL::Device* dev, MTL::CommandQueue* queue, MTL::AccelerationStructure* blas)
{
	MTL::Buffer* instBuf = dev->newBuffer(sizeof(MTL::AccelerationStructureInstanceDescriptor), MTL::ResourceStorageModeShared);
	MTL::AccelerationStructureInstanceDescriptor* inst = (MTL::AccelerationStructureInstanceDescriptor*)instBuf->contents();
	memset(inst, 0, sizeof(*inst));
	inst->transformationMatrix = MTL::PackedFloat4x3(
		  MTL::PackedFloat3(1.0f, 0.0f, 0.0f)
		, MTL::PackedFloat3(0.0f, 1.0f, 0.0f)
		, MTL::PackedFloat3(0.0f, 0.0f, 1.0f)
		, MTL::PackedFloat3(0.0f, 0.0f, 0.0f)
		);
	inst->options = MTL::AccelerationStructureInstanceOptionDisableTriangleCulling;
	inst->mask    = 0xff;
	inst->intersectionFunctionTableOffset = 0;
	inst->accelerationStructureIndex      = 0;

	MTL::InstanceAccelerationStructureDescriptor* desc = MTL::InstanceAccelerationStructureDescriptor::alloc()->init();
	const NS::Object* blases[1] = { blas };
	desc->setInstancedAccelerationStructures(NS::Array::array(blases, 1));
	desc->setInstanceCount(1);
	desc->setInstanceDescriptorBuffer(instBuf);

	MTL::AccelerationStructure* tlas = buildAs(dev, queue, desc);
	desc->release();
	// instBuf intentionally leaked for spike brevity (needed only during the build).
	return tlas;
}

// Returns the count of pixels whose red channel matches `expect` (out of w*h) and the
// center value via out param.
static uint32_t runPhase(MTL::Device* dev, MTL::CommandQueue* queue
	, MTL::ComputePipelineState* pso
	, MTL::VisibleFunctionTable* vft
	, MTL::IntersectionFunctionTable* ift  // NULL for the triangle phase
	, MTL::AccelerationStructure* tlas, MTL::AccelerationStructure* blas
	, uint8_t expect, uint8_t* center)
{
	const uint32_t kW = 64, kH = 64;

	MTL::TextureDescriptor* td = MTL::TextureDescriptor::texture2DDescriptor(MTL::PixelFormatRGBA8Unorm, kW, kH, false);
	td->setUsage(MTL::TextureUsageShaderWrite | MTL::TextureUsageShaderRead);
	MTL::Texture* target = dev->newTexture(td);

	MTL::Buffer* sbt = dev->newBuffer(8, MTL::ResourceStorageModeShared);
	((uint32_t*)sbt->contents())[0] = 0; // miss   -> table index 0
	((uint32_t*)sbt->contents())[1] = 1; // "hit"  -> table index 1

	MTL::CommandBuffer* cmd = queue->commandBuffer();
	MTL::ComputeCommandEncoder* enc = cmd->computeCommandEncoder();
	enc->setComputePipelineState(pso);
	enc->setAccelerationStructure(tlas, 0);
	enc->setVisibleFunctionTable(vft, 1);
	enc->setBuffer(sbt, 0, 2);
	if (ift)
	{
		enc->setIntersectionFunctionTable(ift, 3);
	}
	enc->setTexture(target, 0);
	enc->useResource(tlas, MTL::ResourceUsageRead);
	enc->useResource(blas, MTL::ResourceUsageRead);
	enc->dispatchThreads(MTL::Size(kW, kH, 1), MTL::Size(8, 8, 1));
	enc->endEncoding();
	cmd->commit();
	cmd->waitUntilCompleted();

	std::vector<uint8_t> pixels(kW*kH*4);
	target->getBytes(pixels.data(), kW*4, MTL::Region(0, 0, kW, kH), 0);

	uint32_t good = 0;
	for (uint32_t i = 0; i < kW*kH; ++i)
	{
		if (pixels[i*4] >= expect - 2 && pixels[i*4] <= expect + 2) ++good;
	}
	*center = pixels[(kH/2*kW + kW/2)*4];

	target->release(); sbt->release(); td->release();
	return good;
}

int main()
{
	MTL::Device* dev = MTL::CreateSystemDefaultDevice();
	if (!dev) { printf("no Metal device\n"); return 1; }
	printf("device: %s  raytracing=%d functionPointers=%d\n"
		, dev->name()->utf8String(), dev->supportsRaytracing(), dev->supportsFunctionPointers());
	if (!dev->supportsRaytracing() || !dev->supportsFunctionPointers())
	{
		printf("RESULT: SKIP (missing raytracing or function-pointer support)\n");
		return 0;
	}

	MTL::CommandQueue* queue = dev->newCommandQueue();

	// ---- library + functions ----
	NS::Error* err = NULL;
	MTL::CompileOptions* copts = MTL::CompileOptions::alloc()->init();
	copts->setLanguageVersion(MTL::LanguageVersion2_4);
	MTL::Library* lib = dev->newLibrary(NS::String::string(kMsl, NS::UTF8StringEncoding), copts, &err);
	if (!lib) { printf("MSL compile failed: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 1; }

	MTL::Function* fnMiss  = lib->newFunction(NS::String::string("missFn", NS::UTF8StringEncoding));
	MTL::Function* fnChit  = lib->newFunction(NS::String::string("chitFn", NS::UTF8StringEncoding));
	MTL::Function* fnIsect = lib->newFunction(NS::String::string("sphereIsect", NS::UTF8StringEncoding));
	MTL::Function* fnRgTri = lib->newFunction(NS::String::string("rgTriangle", NS::UTF8StringEncoding));
	MTL::Function* fnRgPro = lib->newFunction(NS::String::string("rgProcedural", NS::UTF8StringEncoding));
	printf("functions: miss=%p chit=%p isect=%p rgTri=%p rgProc=%p\n"
		, (void*)fnMiss, (void*)fnChit, (void*)fnIsect, (void*)fnRgTri, (void*)fnRgPro);

	// ---- geometry ----
	// Phase A triangle at z=4.2 so both phases validate the same analytic distance.
	static const float verts[9] = { -2.0f, -2.0f, 4.2f,  2.0f, -2.0f, 4.2f,  0.0f, 2.0f, 4.2f };
	static const uint16_t indices[3] = { 0, 1, 2 };
	MTL::Buffer* vb = dev->newBuffer(verts, sizeof(verts), MTL::ResourceStorageModeShared);
	MTL::Buffer* ib = dev->newBuffer(indices, sizeof(indices), MTL::ResourceStorageModeShared);

	MTL::AccelerationStructureTriangleGeometryDescriptor* triGeo = MTL::AccelerationStructureTriangleGeometryDescriptor::alloc()->init();
	triGeo->setOpaque(true);
	triGeo->setVertexBuffer(vb);
	triGeo->setVertexStride(12);
	triGeo->setVertexFormat(MTL::AttributeFormatFloat3);
	triGeo->setIndexBuffer(ib);
	triGeo->setIndexType(MTL::IndexTypeUInt16);
	triGeo->setTriangleCount(1);
	MTL::PrimitiveAccelerationStructureDescriptor* triDesc = MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
	{
		const NS::Object* geos[1] = { triGeo };
		triDesc->setGeometryDescriptors(NS::Array::array(geos, 1));
	}
	MTL::AccelerationStructure* triBlas = buildAs(dev, queue, triDesc);
	MTL::AccelerationStructure* triTlas = buildTlas(dev, queue, triBlas);

	// Phase B: one AABB around the sphere (centre (0,0,5), r=0.8).
	static const float aabb[6] = { -1.0f, -1.0f, 4.0f, 1.0f, 1.0f, 6.0f };
	MTL::Buffer* ab = dev->newBuffer(aabb, sizeof(aabb), MTL::ResourceStorageModeShared);
	MTL::AccelerationStructureBoundingBoxGeometryDescriptor* boxGeo = MTL::AccelerationStructureBoundingBoxGeometryDescriptor::alloc()->init();
	boxGeo->setOpaque(true);
	boxGeo->setBoundingBoxBuffer(ab);
	boxGeo->setBoundingBoxStride(24);
	boxGeo->setBoundingBoxCount(1);
	boxGeo->setIntersectionFunctionTableOffset(0);
	MTL::PrimitiveAccelerationStructureDescriptor* boxDesc = MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
	{
		const NS::Object* geos[1] = { boxGeo };
		boxDesc->setGeometryDescriptors(NS::Array::array(geos, 1));
	}
	MTL::AccelerationStructure* boxBlas = buildAs(dev, queue, boxDesc);
	MTL::AccelerationStructure* boxTlas = buildTlas(dev, queue, boxBlas);

	// ---- phase A pipeline: raygen kernel + linked visible functions + table ----
	MTL::LinkedFunctions* lfTri = MTL::LinkedFunctions::alloc()->init();
	{
		const NS::Object* fns[2] = { fnMiss, fnChit };
		lfTri->setFunctions(NS::Array::array(fns, 2));
	}
	MTL::ComputePipelineDescriptor* pdTri = MTL::ComputePipelineDescriptor::alloc()->init();
	pdTri->setComputeFunction(fnRgTri);
	pdTri->setLinkedFunctions(lfTri);
	MTL::ComputePipelineState* psoTri = dev->newComputePipelineState(pdTri, MTL::PipelineOptionNone, NULL, &err);
	if (!psoTri) { printf("phase A pipeline failed: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 1; }

	MTL::VisibleFunctionTableDescriptor* vtd = MTL::VisibleFunctionTableDescriptor::alloc()->init();
	vtd->setFunctionCount(2);
	MTL::VisibleFunctionTable* vftTri = psoTri->newVisibleFunctionTable(vtd);
	vftTri->setFunction(psoTri->functionHandle(fnMiss), 0);
	vftTri->setFunction(psoTri->functionHandle(fnChit), 1);

	uint8_t center = 0;
	uint32_t good = runPhase(dev, queue, psoTri, vftTri, NULL, triTlas, triBlas, 191, &center);
	printf("phase A (visible-function SBT, triangle): %u / 4096 at 0.75   center=%u\n", good, center);
	const bool passA = good > 4000;
	printf(passA ? "RESULT_A: PASS\n" : "RESULT_A: FAIL\n");

	// ---- phase B pipeline: + the intersection function in the linked set + IFT ----
	MTL::LinkedFunctions* lfPro = MTL::LinkedFunctions::alloc()->init();
	{
		const NS::Object* fns[3] = { fnMiss, fnChit, fnIsect };
		lfPro->setFunctions(NS::Array::array(fns, 3));
	}
	MTL::ComputePipelineDescriptor* pdPro = MTL::ComputePipelineDescriptor::alloc()->init();
	pdPro->setComputeFunction(fnRgPro);
	pdPro->setLinkedFunctions(lfPro);
	MTL::ComputePipelineState* psoPro = dev->newComputePipelineState(pdPro, MTL::PipelineOptionNone, NULL, &err);
	if (!psoPro) { printf("phase B pipeline failed: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 1; }

	MTL::VisibleFunctionTable* vftPro = psoPro->newVisibleFunctionTable(vtd);
	vftPro->setFunction(psoPro->functionHandle(fnMiss), 0);
	vftPro->setFunction(psoPro->functionHandle(fnChit), 1);

	MTL::IntersectionFunctionTableDescriptor* itd = MTL::IntersectionFunctionTableDescriptor::alloc()->init();
	itd->setFunctionCount(1);
	MTL::IntersectionFunctionTable* ift = psoPro->newIntersectionFunctionTable(itd);
	ift->setFunction(psoPro->functionHandle(fnIsect), 0);

	good = runPhase(dev, queue, psoPro, vftPro, ift, boxTlas, boxBlas, 191, &center);
	printf("phase B (intersection function table, procedural sphere): %u / 4096 at 0.75   center=%u\n", good, center);
	const bool passB = good > 4000;
	printf(passB ? "RESULT_B: PASS\n" : "RESULT_B: FAIL\n");

	printf("%s\n", (passA && passB)
		? "SPIKE: the Metal function-table runtime model works end to end on this device."
		: "SPIKE: FAILED");
	return (passA && passB) ? 0 : 3;
}
