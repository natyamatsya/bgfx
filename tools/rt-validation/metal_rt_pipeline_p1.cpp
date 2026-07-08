// Metal RT-pipeline P1 END-TO-END: Slang-compiled anyhit + intersection stages running
// on-device through the extended runtime contract — the P0 pieces (visible-function SBT
// at [[buffer(30)]], slang_RTSbt at [[buffer(29)]], slang_RTGlobals at [[buffer(28)]])
// plus the P1 intersection function table `slang_rtIsect` at [[buffer(27)]].
//
// Phase A (procedural sphere): a Slang intersection shader in an AABB BLAS reports the
//   analytic entry with a custom hit kind and a user attribute struct; the closest-hit
//   validates distance, hit kind, and the attribute blob. Expected 1.0
//   (0.5 = wrong kind+attrs, 0.75 = one of them wrong, 0.25 = bare hit only).
// Phase B (anyhit): a non-opaque triangle with a Slang anyhit that writes 0.5 into the
//   payload and rejects the candidate. Expected exactly 0.5 — the write persisted (DXR
//   payload-persistence-on-ignore) AND the reject forced a miss (0.25 = anyhit never
//   ran; 0.75 = reject failed and the closest-hit also ran).
//
// Usage: metal_rt_pipeline_p1 <combined.metal>
// (one module holding all five stages -- the design doc's separate-compilation caveat
// means the raygen kernel only receives the slang_rtIsect binding when the
// anyhit/intersection stages are compiled with it)
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

static MTL::Library* loadStageLibrary(MTL::Device* dev, const char* path)
{
	std::string src = loadText(path);
	if (src.empty()) return nullptr;
	NS::Error* err = nullptr;
	MTL::CompileOptions* opts = MTL::CompileOptions::alloc()->init();
	opts->setLanguageVersion(MTL::LanguageVersion3_1);
	MTL::Library* lib = dev->newLibrary(NS::String::string(src.c_str(), NS::UTF8StringEncoding), opts, &err);
	opts->release();
	if (!lib)
	{
		printf("MSL compile failed for %s: %s\n", path, err ? err->localizedDescription()->utf8String() : "?");
	}
	return lib;
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
	return tlas;
}

struct SlangRTSbt
{
	uint32_t missBase;
	uint32_t hitBase;
	uint32_t callableBase;
	uint32_t hitStride;
	uint64_t instanceSbtOffsets;
};

// Build the "RT program" for one phase — kernel + linked handler/intersection
// functions, visible + intersection function tables, software SBT — and trace 64x64.
// Returns the count of pixels whose red channel is `expect` (±2) and the center value.
static uint32_t runPhase(MTL::Device* dev, MTL::CommandQueue* queue
	, MTL::Function* fnRg, MTL::Function* fnMiss, MTL::Function* fnChit, MTL::Function* fnIsect
	, MTL::AccelerationStructure* tlas, MTL::AccelerationStructure* blas
	, uint8_t expect, uint8_t* center)
{
	const uint32_t kW = 64, kH = 64;
	NS::Error* err = nullptr;

	MTL::LinkedFunctions* linked = MTL::LinkedFunctions::alloc()->init();
	{
		const NS::Object* fns[3] = { fnMiss, fnChit, fnIsect };
		linked->setFunctions(NS::Array::array(fns, 3));
	}
	MTL::ComputePipelineDescriptor* pd = MTL::ComputePipelineDescriptor::alloc()->init();
	pd->setComputeFunction(fnRg);
	pd->setLinkedFunctions(linked);
	MTL::ComputePipelineState* pso = dev->newComputePipelineState(pd, MTL::PipelineOptionNone, nullptr, &err);
	if (!pso) { printf("pipeline failed: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 0; }

	MTL::VisibleFunctionTableDescriptor* vtd = MTL::VisibleFunctionTableDescriptor::alloc()->init();
	vtd->setFunctionCount(2);
	MTL::VisibleFunctionTable* vft = pso->newVisibleFunctionTable(vtd);
	vft->setFunction(pso->functionHandle(fnMiss), 0);
	vft->setFunction(pso->functionHandle(fnChit), 1);

	MTL::IntersectionFunctionTableDescriptor* itd = MTL::IntersectionFunctionTableDescriptor::alloc()->init();
	itd->setFunctionCount(1);
	MTL::IntersectionFunctionTable* ift = pso->newIntersectionFunctionTable(itd);
	ift->setFunction(pso->functionHandle(fnIsect), 0);

	MTL::Buffer* instOffsets = dev->newBuffer(sizeof(uint32_t), MTL::ResourceStorageModeShared);
	*(uint32_t*)instOffsets->contents() = 0;
	MTL::Buffer* sbtBuf = dev->newBuffer(sizeof(SlangRTSbt), MTL::ResourceStorageModeShared);
	SlangRTSbt* sbt = (SlangRTSbt*)sbtBuf->contents();
	sbt->missBase = 0;
	sbt->hitBase = 1;
	sbt->callableBase = 0;
	sbt->hitStride = 1;
	sbt->instanceSbtOffsets = instOffsets->gpuAddress();
	MTL::Buffer* globalsBuf = dev->newBuffer(4, MTL::ResourceStorageModeShared);

	MTL::TextureDescriptor* td = MTL::TextureDescriptor::texture2DDescriptor(MTL::PixelFormatRGBA8Unorm, kW, kH, false);
	td->setUsage(MTL::TextureUsageShaderWrite | MTL::TextureUsageShaderRead);
	MTL::Texture* target = dev->newTexture(td);

	MTL::CommandBuffer* cmd = queue->commandBuffer();
	MTL::ComputeCommandEncoder* enc = cmd->computeCommandEncoder();
	enc->setComputePipelineState(pso);
	enc->setAccelerationStructure(tlas, 0);        // scene  [[buffer(0)]]
	enc->setTexture(target, 0);                    // target [[texture(0)]]
	enc->setIntersectionFunctionTable(ift, 27);    // slang_rtIsect    [[buffer(27)]]
	enc->setBuffer(globalsBuf, 0, 28);             // slang_rtGlobals  [[buffer(28)]]
	enc->setBuffer(sbtBuf, 0, 29);                 // slang_rtSbt      [[buffer(29)]]
	enc->setVisibleFunctionTable(vft, 30);         // slang_rtHandlers [[buffer(30)]]
	enc->useResource(tlas, MTL::ResourceUsageRead);
	enc->useResource(blas, MTL::ResourceUsageRead);
	enc->useResource(instOffsets, MTL::ResourceUsageRead);
	enc->dispatchThreads(MTL::Size(kW, kH, 1), MTL::Size(8, 8, 1));
	enc->endEncoding();
	cmd->commit();
	cmd->waitUntilCompleted();

	std::vector<uint8_t> pixels(kW*kH*4);
	target->getBytes(pixels.data(), kW*4, MTL::Region(0, 0, kW, kH), 0);
	uint32_t good = 0;
	for (uint32_t i = 0; i < kW*kH; ++i)
		if (pixels[i*4] >= expect - 2 && pixels[i*4] <= expect + 2) ++good;
	*center = pixels[(kH/2*kW + kW/2)*4];
	return good;
}

int main(int argc, char** argv)
{
	if (argc < 2) { printf("usage: %s <combined.metal>\n", argv[0]); return 1; }

	MTL::Device* dev = MTL::CreateSystemDefaultDevice();
	if (!dev) { printf("no Metal device\n"); return 1; }
	printf("device: %s  raytracing=%d functionPointers=%d\n"
		, dev->name()->utf8String(), dev->supportsRaytracing(), dev->supportsFunctionPointers());
	if (!dev->supportsRaytracing() || !dev->supportsFunctionPointers()) { printf("RESULT: SKIP\n"); return 0; }
	MTL::CommandQueue* queue = dev->newCommandQueue();

	MTL::Library* lib = loadStageLibrary(dev, argv[1]);
	if (!lib) return 1;
	printf("stage functions:\n");
	MTL::Function* fnRg    = stageFunction(lib, "rayGenMain");
	MTL::Function* fnMiss  = stageFunction(lib, "missMain");
	MTL::Function* fnChit  = stageFunction(lib, "closestHitMain");
	MTL::Function* fnIsect = stageFunction(lib, "sphereIsect");
	MTL::Function* fnAhit  = stageFunction(lib, "anyHitMain");
	if (!fnRg || !fnMiss || !fnChit || !fnIsect || !fnAhit) return 1;

	// Phase A scene: one AABB around the sphere.
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

	uint8_t center = 0;
	uint32_t good = runPhase(dev, queue, fnRg, fnMiss, fnChit, fnIsect, boxTlas, boxBlas, 255, &center);
	printf("phase A (Slang intersection fn, user attrs, hit kind): %u / 4096 at 1.0   center=%u\n", good, center);
	const bool passA = good > 4088;
	printf(passA ? "RESULT_A: PASS\n" : "RESULT_A: FAIL\n");

	// Phase B scene: one NON-opaque triangle at z=5 (so the anyhit runs without flags).
	static const float verts[9] = { -2.0f, -2.0f, 5.0f,  2.0f, -2.0f, 5.0f,  0.0f, 2.0f, 5.0f };
	static const uint16_t indices[3] = { 0, 1, 2 };
	MTL::Buffer* vb = dev->newBuffer(verts, sizeof(verts), MTL::ResourceStorageModeShared);
	MTL::Buffer* ib = dev->newBuffer(indices, sizeof(indices), MTL::ResourceStorageModeShared);
	MTL::AccelerationStructureTriangleGeometryDescriptor* triGeo = MTL::AccelerationStructureTriangleGeometryDescriptor::alloc()->init();
	triGeo->setOpaque(false);
	triGeo->setVertexBuffer(vb);
	triGeo->setVertexStride(12);
	triGeo->setVertexFormat(MTL::AttributeFormatFloat3);
	triGeo->setIndexBuffer(ib);
	triGeo->setIndexType(MTL::IndexTypeUInt16);
	triGeo->setTriangleCount(1);
	triGeo->setIntersectionFunctionTableOffset(0);
	MTL::PrimitiveAccelerationStructureDescriptor* triDesc = MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
	{
		const NS::Object* geos[1] = { triGeo };
		triDesc->setGeometryDescriptors(NS::Array::array(geos, 1));
	}
	MTL::AccelerationStructure* triBlas = buildAs(dev, queue, triDesc);
	MTL::AccelerationStructure* triTlas = buildTlas(dev, queue, triBlas);

	good = runPhase(dev, queue, fnRg, fnMiss, fnChit, fnAhit, triTlas, triBlas, 128, &center);
	printf("phase B (Slang anyhit: payload persists + reject forces miss): %u / 4096 at 0.5   center=%u\n", good, center);
	const bool passB = good > 4088;
	printf(passB ? "RESULT_B: PASS\n" : "RESULT_B: FAIL\n");

	printf("%s\n", (passA && passB)
		? "P1 END-TO-END: compiler-emitted intersection + anyhit stages work on-device."
		: "P1 END-TO-END: FAILED");
	return (passA && passB) ? 0 : 3;
}
