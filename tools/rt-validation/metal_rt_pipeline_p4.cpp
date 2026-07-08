// Metal RT-pipeline P4 END-TO-END: the world-/object-space semantics fix under a
// NON-IDENTITY instance transform, plus RAY_FLAG_SKIP_CLOSEST_HIT_SHADER.
//
// The AABB BLAS lives at OBJECT-space z in [2,4]; the instance translates it +2z, so
// the sphere the intersection shader tests at WORLD (0,0,5) is only found when
// WorldRayOrigin/Direction really are world-space (the pre-P4 bug aliased them to
// Metal's object-space [[origin]]/[[direction]] and this scene then reports no hit).
// Expected exactly 1.0; 0.5 = world/object bug (both sphere traces dented),
// see rt_p4_all.slang for the full value breakdown.
//
// Usage: metal_rt_pipeline_p4 <combined.metal>
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#define NS_PRIVATE_IMPLEMENTATION
#include <metal-cpp/metal.hpp>
#include "metal_rt_host.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// Build the "RT program" for one phase — kernel + linked handler/intersection
// functions, visible + intersection function tables, software SBT — and trace 64x64.
// Returns the count of pixels whose red channel is `expect` (±2) and the center value.
static uint32_t runPhase(MTL::Device* dev, MTL::CommandQueue* queue
	, MTL::Function* fnRg, MTL::Function* fnMiss, MTL::Function* fnMiss2, MTL::Function* fnChit, MTL::Function* fnIsect
	, MTL::AccelerationStructure* tlas, MTL::AccelerationStructure* blas
	, uint8_t expect, uint8_t* center)
{
	const uint32_t kW = 64, kH = 64;
	NS::Error* err = nullptr;

	MTL::LinkedFunctions* linked = MTL::LinkedFunctions::alloc()->init();
	{
		const NS::Object* fns[4] = { fnMiss, fnMiss2, fnChit, fnIsect };
		linked->setFunctions(NS::Array::array(fns, 4));
	}
	MTL::ComputePipelineDescriptor* pd = MTL::ComputePipelineDescriptor::alloc()->init();
	pd->setComputeFunction(fnRg);
	pd->setLinkedFunctions(linked);
	MTL::ComputePipelineState* pso = dev->newComputePipelineState(pd, MTL::PipelineOptionNone, nullptr, &err);
	if (!pso) { printf("pipeline failed: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 0; }

	MTL::VisibleFunctionTableDescriptor* vtd = MTL::VisibleFunctionTableDescriptor::alloc()->init();
	vtd->setFunctionCount(3);
	MTL::VisibleFunctionTable* vft = pso->newVisibleFunctionTable(vtd);
	vft->setFunction(pso->functionHandle(fnMiss), 0);
	vft->setFunction(pso->functionHandle(fnMiss2), 1);
	vft->setFunction(pso->functionHandle(fnChit), 2);

	MTL::IntersectionFunctionTableDescriptor* itd = MTL::IntersectionFunctionTableDescriptor::alloc()->init();
	itd->setFunctionCount(1);
	MTL::IntersectionFunctionTable* ift = pso->newIntersectionFunctionTable(itd);
	ift->setFunction(pso->functionHandle(fnIsect), 0);

	MTL::Buffer* instOffsets = dev->newBuffer(sizeof(uint32_t), MTL::ResourceStorageModeShared);
	*(uint32_t*)instOffsets->contents() = 0;
	MTL::Buffer* sbtBuf = dev->newBuffer(sizeof(SlangRTSbt), MTL::ResourceStorageModeShared);
	SlangRTSbt* sbt = (SlangRTSbt*)sbtBuf->contents();
	sbt->missBase = 0;
	sbt->hitBase = 2;
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
	MTL::Function* fnMiss2 = stageFunction(lib, "shadowMiss");
	MTL::Function* fnChit  = stageFunction(lib, "closestHitMain");
	MTL::Function* fnIsect = stageFunction(lib, "sphereIsect");
	if (!fnRg || !fnMiss || !fnMiss2 || !fnChit || !fnIsect) return 1;

	// AABB in OBJECT space: z in [2,4] (the +2z instance transform puts it at world [4,6]).
	static const float aabb[6] = { -1.0f, -1.0f, 2.0f, 1.0f, 1.0f, 4.0f };
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
	MTL::AccelerationStructure* boxTlas = buildTlas(dev, queue, boxBlas, 2.0f);

	uint8_t center = 0;
	uint32_t good = runPhase(dev, queue, fnRg, fnMiss, fnMiss2, fnChit, fnIsect, boxTlas, boxBlas, 255, &center);
	printf("translated-instance module (p4 semantics / p5 transforms): %u / 4096 at 1.0   center=%u\n", good, center);
	const bool pass = good > 4088;
	printf(pass ? "RESULT: PASS\n" : "RESULT: FAIL\n");
	return pass ? 0 : 3;
}
