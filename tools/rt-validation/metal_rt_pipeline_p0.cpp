// Metal RT-pipeline P0 END-TO-END: runs SLANG-COMPILED ray-tracing stages (the fork's
// native Metal P0 backend, docs/design/metal-raytracing.md in the slang repo) on-device
// through the buffer(28..30) + slang_RTSbt runtime contract this host implements — the
// same contract bgfx's Metal createRtProgram will use. Where metal_rt_pipeline_spike.cpp
// proved the runtime model with hand-written MSL, this closes the loop with real
// compiler output.
//
// Usage: metal_rt_pipeline_p0 <rg.metal> <miss0.metal> <miss1.metal> <chit.metal>
// The stage sources come from:
//   slangc tools/rt-validation/p0/rt_p0_*.slang -target metal -o ...
// Expected image: every pixel exactly 1.0 (255) — closest-hit 0.5 + distance check 0.25
// via SBT hit record, plus miss-record-1 routing 0.25. Failure signatures: 191 = miss-1
// routing broken, 128 = distance/context broken, 64 = hit routing broken.
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

// One .metal source file holds exactly one Slang entry point (a [[kernel]] or a
// [[visible]] function); compile it and return that function.
static MTL::Function* loadStageFunction(MTL::Device* dev, const char* path)
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
		return nullptr;
	}
	NS::Array* names = lib->functionNames();
	if (names->count() != 1)
	{
		printf("%s: expected exactly one entry function, got %lu\n", path, (unsigned long)names->count());
		return nullptr;
	}
	MTL::Function* fn = lib->newFunction((NS::String*)names->object(0));
	printf("  %-14s -> %s\n", fn->name()->utf8String(), path);
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

// The slang_RTSbt struct of the contract: region bases into the visible function
// table plus the per-instance hit-group contributions (a device address).
struct SlangRTSbt
{
	uint32_t missBase;
	uint32_t hitBase;
	uint32_t callableBase;
	uint32_t hitStride;
	uint64_t instanceSbtOffsets; // device uint*
};
static_assert(sizeof(SlangRTSbt) == 24, "must match the MSL layout");

int main(int argc, char** argv)
{
	if (argc < 5) { printf("usage: %s <rg.metal> <miss0.metal> <miss1.metal> <chit.metal>\n", argv[0]); return 1; }
	const uint32_t kW = 64, kH = 64;

	MTL::Device* dev = MTL::CreateSystemDefaultDevice();
	if (!dev) { printf("no Metal device\n"); return 1; }
	printf("device: %s  raytracing=%d functionPointers=%d\n"
		, dev->name()->utf8String(), dev->supportsRaytracing(), dev->supportsFunctionPointers());
	if (!dev->supportsRaytracing() || !dev->supportsFunctionPointers())
	{
		printf("RESULT: SKIP\n");
		return 0;
	}
	MTL::CommandQueue* queue = dev->newCommandQueue();

	// ---- Slang-compiled stage functions ----
	printf("stage functions:\n");
	MTL::Function* fnRg    = loadStageFunction(dev, argv[1]);
	MTL::Function* fnMiss0 = loadStageFunction(dev, argv[2]);
	MTL::Function* fnMiss1 = loadStageFunction(dev, argv[3]);
	MTL::Function* fnChit  = loadStageFunction(dev, argv[4]);
	if (!fnRg || !fnMiss0 || !fnMiss1 || !fnChit) return 1;

	// ---- scene: one triangle at z=5 straddling the +Z axis ----
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
	inst->options = MTL::AccelerationStructureInstanceOptionDisableTriangleCulling | MTL::AccelerationStructureInstanceOptionOpaque;
	inst->mask    = 0xff;
	inst->accelerationStructureIndex = 0;
	MTL::InstanceAccelerationStructureDescriptor* tlasDesc = MTL::InstanceAccelerationStructureDescriptor::alloc()->init();
	{
		const NS::Object* blases[1] = { blas };
		tlasDesc->setInstancedAccelerationStructures(NS::Array::array(blases, 1));
	}
	tlasDesc->setInstanceCount(1);
	tlasDesc->setInstanceDescriptorBuffer(instBuf);
	MTL::AccelerationStructure* tlas = buildAs(dev, queue, tlasDesc);

	// ---- the RT "program": kernel + linked handlers, tables, software SBT ----
	// (this block is exactly what bgfx::createRtProgram does on Metal)
	NS::Error* err = nullptr;
	MTL::LinkedFunctions* linked = MTL::LinkedFunctions::alloc()->init();
	{
		const NS::Object* fns[3] = { fnMiss0, fnMiss1, fnChit };
		linked->setFunctions(NS::Array::array(fns, 3));
	}
	MTL::ComputePipelineDescriptor* pd = MTL::ComputePipelineDescriptor::alloc()->init();
	pd->setComputeFunction(fnRg);
	pd->setLinkedFunctions(linked);
	MTL::ComputePipelineState* pso = dev->newComputePipelineState(pd, MTL::PipelineOptionNone, nullptr, &err);
	if (!pso) { printf("pipeline failed: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 1; }

	// Visible function table = the SBT records: [miss0, miss1, chit].
	MTL::VisibleFunctionTableDescriptor* vtd = MTL::VisibleFunctionTableDescriptor::alloc()->init();
	vtd->setFunctionCount(3);
	MTL::VisibleFunctionTable* vft = pso->newVisibleFunctionTable(vtd);
	vft->setFunction(pso->functionHandle(fnMiss0), 0);
	vft->setFunction(pso->functionHandle(fnMiss1), 1);
	vft->setFunction(pso->functionHandle(fnChit), 2);

	// Per-instance hit-group contributions (DXR InstanceContributionToHitGroupIndex).
	MTL::Buffer* instOffsets = dev->newBuffer(sizeof(uint32_t), MTL::ResourceStorageModeShared);
	*(uint32_t*)instOffsets->contents() = 0;

	MTL::Buffer* sbtBuf = dev->newBuffer(sizeof(SlangRTSbt), MTL::ResourceStorageModeShared);
	SlangRTSbt* sbt = (SlangRTSbt*)sbtBuf->contents();
	sbt->missBase = 0;
	sbt->hitBase = 2;
	sbt->callableBase = 0;
	sbt->hitStride = 1;
	sbt->instanceSbtOffsets = instOffsets->gpuAddress();

	// slang_RTGlobals: hoisting not implemented in P0; one reserved uint.
	MTL::Buffer* globalsBuf = dev->newBuffer(4, MTL::ResourceStorageModeShared);

	// ---- output + dispatch (this block is bgfx's RT dispatch path) ----
	MTL::TextureDescriptor* td = MTL::TextureDescriptor::texture2DDescriptor(MTL::PixelFormatRGBA8Unorm, kW, kH, false);
	td->setUsage(MTL::TextureUsageShaderWrite | MTL::TextureUsageShaderRead);
	MTL::Texture* targetTex = dev->newTexture(td);

	MTL::CommandBuffer* cmd = queue->commandBuffer();
	MTL::ComputeCommandEncoder* enc = cmd->computeCommandEncoder();
	enc->setComputePipelineState(pso);
	// user bindings, at the indices Slang's Metal layout assigned:
	enc->setAccelerationStructure(tlas, 0);   // scene   [[buffer(0)]]
	enc->setTexture(targetTex, 0);            // target  [[texture(0)]]
	// the contract's system bindings:
	enc->setBuffer(globalsBuf, 0, 28);        // slang_rtGlobals [[buffer(28)]]
	enc->setBuffer(sbtBuf, 0, 29);            // slang_rtSbt     [[buffer(29)]]
	enc->setVisibleFunctionTable(vft, 30);    // slang_rtHandlers [[buffer(30)]]
	enc->useResource(tlas, MTL::ResourceUsageRead);
	enc->useResource(blas, MTL::ResourceUsageRead);
	enc->useResource(instOffsets, MTL::ResourceUsageRead);
	enc->dispatchThreads(MTL::Size(kW, kH, 1), MTL::Size(8, 8, 1));
	enc->endEncoding();
	cmd->commit();
	cmd->waitUntilCompleted();

	std::vector<uint8_t> pixels(kW*kH*4);
	targetTex->getBytes(pixels.data(), kW*4, MTL::Region(0, 0, kW, kH), 0);

	uint32_t full = 0;
	for (uint32_t i = 0; i < kW*kH; ++i)
	{
		if (pixels[i*4] >= 253) ++full;
	}
	uint8_t center = pixels[(kH/2*kW + kW/2)*4];
	printf("slang-compiled P0 pipeline: %u / %u pixels at 1.0   center=%u\n", full, kW*kH, center);
	const bool pass = full > (kW*kH - 8);
	printf(pass ? "RESULT: PASS (compiler-emitted stages through the runtime contract)\n"
	            : "RESULT: FAIL\n");
	return pass ? 0 : 3;
}
