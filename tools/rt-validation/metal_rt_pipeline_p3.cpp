// Metal RT-pipeline P3 END-TO-END — the design doc's §11 question 1 gate, on-device:
// TraceRay FROM A CLOSEST-HIT [[visible]] function (recursion depth 2), dispatching
// through the slang_RTGlobals ARGUMENT BUFFER (P3 ABI: the dispatch-state header
// {handlers, isect, sbt} followed by the hoisted user resources in declaration order),
// plus CallShader (P2) from both the kernel and a handler, hoisted-resource access, and
// the entry-snapshot guarantee (system values read after a nested trace).
//
// Expected image: every pixel exactly 1.0 — see rt_p3_all.slang for the additive
// breakdown; each P2/P3 mechanism contributes a distinct increment.
//
// slang_RTGlobals encoding (56 bytes, from the emitted MSL):
//   @0  handlers  visible_function_table  (gpuResourceID)
//   @8  isect     intersection_function_table (0 here: no isect/ahit stages linked)
//   @16 sbt       { missBase, hitBase, callableBase, hitStride, device uint* offsets }
//   @40 scene     acceleration_structure  (gpuResourceID)
//   @48 materials device packed_float4*   (gpuAddress)
//
// Usage: metal_rt_pipeline_p3 <combined.metal>
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#define NS_PRIVATE_IMPLEMENTATION
#include <metal-cpp/metal.hpp>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

static std::string loadText(const char* path)
{
	FILE* f = fopen(path, "rb");
	if (!f) { printf("cannot open %s\n", path); return {}; }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	std::string s((size_t)n, '\0');
	if (fread(&s[0], 1, n, f) != (size_t)n) { fclose(f); return {}; }
	fclose(f);
	return s;
}

static MTL::Function* stageFunction(MTL::Library* lib, const char* name)
{
	MTL::Function* fn = lib->newFunction(NS::String::string(name, NS::UTF8StringEncoding));
	printf("  %-16s %s\n", name, fn ? "ok" : "MISSING");
	return fn;
}

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

struct SlangRTSbt
{
	uint32_t missBase;
	uint32_t hitBase;
	uint32_t callableBase;
	uint32_t hitStride;
	uint64_t instanceSbtOffsets;
};
static_assert(sizeof(SlangRTSbt) == 24, "SBT layout");

// The P3 slang_RTGlobals argument buffer, encoded raw (argument-buffer tier 2 /
// Metal 3 resource IDs).
struct SlangRTGlobals
{
	uint64_t   handlers;   // MTLVisibleFunctionTable gpuResourceID
	uint64_t   isect;      // MTLIntersectionFunctionTable gpuResourceID (0 = none)
	SlangRTSbt sbt;
	uint64_t   scene;      // MTLAccelerationStructure gpuResourceID
	uint64_t   materials;  // device pointer (gpuAddress)
};
static_assert(sizeof(SlangRTGlobals) == 56, "globals layout must match the emitted MSL");

int main(int argc, char** argv)
{
	if (argc < 2) { printf("usage: %s <combined.metal>\n", argv[0]); return 1; }
	const uint32_t kW = 64, kH = 64;

	MTL::Device* dev = MTL::CreateSystemDefaultDevice();
	if (!dev) { printf("no Metal device\n"); return 1; }
	printf("device: %s  raytracing=%d functionPointers=%d\n"
		, dev->name()->utf8String(), dev->supportsRaytracing(), dev->supportsFunctionPointers());
	if (!dev->supportsRaytracing() || !dev->supportsFunctionPointers()) { printf("RESULT: SKIP\n"); return 0; }
	MTL::CommandQueue* queue = dev->newCommandQueue();

	std::string src = loadText(argv[1]);
	if (src.empty()) return 1;
	NS::Error* err = nullptr;
	MTL::CompileOptions* copts = MTL::CompileOptions::alloc()->init();
	copts->setLanguageVersion(MTL::LanguageVersion3_1);
	MTL::Library* lib = dev->newLibrary(NS::String::string(src.c_str(), NS::UTF8StringEncoding), copts, &err);
	if (!lib) { printf("MSL compile failed: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 1; }

	printf("stage functions:\n");
	MTL::Function* fnRg     = stageFunction(lib, "rayGenMain");
	MTL::Function* fnMiss   = stageFunction(lib, "missMain");
	MTL::Function* fnShadow = stageFunction(lib, "shadowMiss");
	MTL::Function* fnChit   = stageFunction(lib, "closestHitMain");
	MTL::Function* fnCall   = stageFunction(lib, "shadeCallable");
	if (!fnRg || !fnMiss || !fnShadow || !fnChit || !fnCall) return 1;

	// Scene: one opaque triangle at z=5; the chit's shadow ray (+y) escapes upward.
	static const float verts[9] = { -2.0f, -2.0f, 5.0f,  2.0f, -2.0f, 5.0f,  0.0f, 2.0f, 5.0f };
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
	MTL::PrimitiveAccelerationStructureDescriptor* blasDesc = MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
	{
		const NS::Object* geos[1] = { triGeo };
		blasDesc->setGeometryDescriptors(NS::Array::array(geos, 1));
	}
	MTL::AccelerationStructure* blas = buildAs(dev, queue, blasDesc);

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
	MTL::InstanceAccelerationStructureDescriptor* tlasDesc = MTL::InstanceAccelerationStructureDescriptor::alloc()->init();
	{
		const NS::Object* blases[1] = { blas };
		tlasDesc->setInstancedAccelerationStructures(NS::Array::array(blases, 1));
	}
	tlasDesc->setInstanceCount(1);
	tlasDesc->setInstanceDescriptorBuffer(instBuf);
	MTL::AccelerationStructure* tlas = buildAs(dev, queue, tlasDesc);

	// Pipeline: raygen kernel + all handler stages linked; a handler-side TraceRay
	// means visible functions nest one level deeper than the kernel's own call.
	MTL::LinkedFunctions* linked = MTL::LinkedFunctions::alloc()->init();
	{
		const NS::Object* fns[4] = { fnMiss, fnShadow, fnChit, fnCall };
		linked->setFunctions(NS::Array::array(fns, 4));
	}
	MTL::ComputePipelineDescriptor* pd = MTL::ComputePipelineDescriptor::alloc()->init();
	pd->setComputeFunction(fnRg);
	pd->setLinkedFunctions(linked);
	pd->setMaxCallStackDepth(2); // kernel -> chit -> {shadowMiss | shadeCallable}
	MTL::ComputePipelineState* pso = dev->newComputePipelineState(pd, MTL::PipelineOptionNone, nullptr, &err);
	if (!pso) { printf("pipeline failed: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 1; }

	// SBT records: [miss0, shadowMiss, chit, callable].
	MTL::VisibleFunctionTableDescriptor* vtd = MTL::VisibleFunctionTableDescriptor::alloc()->init();
	vtd->setFunctionCount(4);
	MTL::VisibleFunctionTable* vft = pso->newVisibleFunctionTable(vtd);
	vft->setFunction(pso->functionHandle(fnMiss), 0);
	vft->setFunction(pso->functionHandle(fnShadow), 1);
	vft->setFunction(pso->functionHandle(fnChit), 2);
	vft->setFunction(pso->functionHandle(fnCall), 3);

	MTL::Buffer* instOffsets = dev->newBuffer(sizeof(uint32_t), MTL::ResourceStorageModeShared);
	*(uint32_t*)instOffsets->contents() = 0;

	SlangRTSbt sbtValue;
	sbtValue.missBase = 0;
	sbtValue.hitBase = 2;
	sbtValue.callableBase = 3;
	sbtValue.hitStride = 1;
	sbtValue.instanceSbtOffsets = instOffsets->gpuAddress();

	MTL::Buffer* sbtBuf = dev->newBuffer(sizeof(SlangRTSbt), MTL::ResourceStorageModeShared);
	memcpy(sbtBuf->contents(), &sbtValue, sizeof(sbtValue));

	static const float mats[4] = { 0.125f, 0.0f, 0.0f, 0.0f };
	MTL::Buffer* materials = dev->newBuffer(mats, sizeof(mats), MTL::ResourceStorageModeShared);

	// The P3 globals argument buffer.
	MTL::Buffer* globalsBuf = dev->newBuffer(sizeof(SlangRTGlobals), MTL::ResourceStorageModeShared);
	SlangRTGlobals* globals = (SlangRTGlobals*)globalsBuf->contents();
	globals->handlers  = vft->gpuResourceID()._impl;
	globals->isect     = 0;
	globals->sbt       = sbtValue;
	globals->scene     = tlas->gpuResourceID()._impl;
	globals->materials = materials->gpuAddress();

	MTL::TextureDescriptor* td = MTL::TextureDescriptor::texture2DDescriptor(MTL::PixelFormatRGBA8Unorm, kW, kH, false);
	td->setUsage(MTL::TextureUsageShaderWrite | MTL::TextureUsageShaderRead);
	MTL::Texture* target = dev->newTexture(td);

	MTL::CommandBuffer* cmd = queue->commandBuffer();
	MTL::ComputeCommandEncoder* enc = cmd->computeCommandEncoder();
	enc->setComputePipelineState(pso);
	enc->setAccelerationStructure(tlas, 0);   // scene     [[buffer(0)]]
	enc->setBuffer(materials, 0, 2);          // materials [[buffer(2)]]
	enc->setTexture(target, 0);               // target    [[texture(0)]]
	enc->setBuffer(globalsBuf, 0, 28);        // slang_rtGlobals  [[buffer(28)]] (real now)
	enc->setBuffer(sbtBuf, 0, 29);            // slang_rtSbt      [[buffer(29)]]
	enc->setVisibleFunctionTable(vft, 30);    // slang_rtHandlers [[buffer(30)]]
	// Residency for everything reachable through the argument buffer as well.
	enc->useResource(tlas, MTL::ResourceUsageRead);
	enc->useResource(blas, MTL::ResourceUsageRead);
	enc->useResource(instOffsets, MTL::ResourceUsageRead);
	enc->useResource(materials, MTL::ResourceUsageRead);
	enc->useResource(vft, MTL::ResourceUsageRead);
	enc->dispatchThreads(MTL::Size(kW, kH, 1), MTL::Size(8, 8, 1));
	enc->endEncoding();
	cmd->commit();
	cmd->waitUntilCompleted();

	std::vector<uint8_t> pixels(kW*kH*4);
	target->getBytes(pixels.data(), kW*4, MTL::Region(0, 0, kW, kH), 0);
	uint32_t good = 0;
	for (uint32_t i = 0; i < kW*kH; ++i)
		if (pixels[i*4] >= 253) ++good;
	uint8_t center = pixels[(kH/2*kW + kW/2)*4];
	printf("P3 recursion + globals + callables: %u / 4096 at 1.0   center=%u\n", good, center);
	const bool pass = good > 4088;
	printf(pass ? "RESULT: PASS — intersector<> works inside [[visible]] functions on this device\n"
	            : "RESULT: FAIL — megakernel fallback stands (see doc §11 q1)\n");
	return pass ? 0 : 3;
}
