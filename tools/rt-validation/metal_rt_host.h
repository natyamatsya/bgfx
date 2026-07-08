// Shared helpers for the standalone Metal RT-pipeline hosts
// (metal_rt_pipeline_p*.cpp): MSL loading, stage-function lookup, acceleration
// structure building, and the software-SBT layout of the runtime contract.
// Include after metal-cpp/metal.hpp (the host translation unit owns the
// *_PRIVATE_IMPLEMENTATION defines).
#pragma once
#include <cstdio>
#include <cstring>
#include <string>

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

// One-instance TLAS with a z-translation (0 = identity placement).
static MTL::AccelerationStructure* buildTlas(MTL::Device* dev, MTL::CommandQueue* queue, MTL::AccelerationStructure* blas, float translateZ)
{
	MTL::Buffer* instBuf = dev->newBuffer(sizeof(MTL::AccelerationStructureInstanceDescriptor), MTL::ResourceStorageModeShared);
	MTL::AccelerationStructureInstanceDescriptor* inst = (MTL::AccelerationStructureInstanceDescriptor*)instBuf->contents();
	memset(inst, 0, sizeof(*inst));
	inst->transformationMatrix = MTL::PackedFloat4x3(
		  MTL::PackedFloat3(1.0f, 0.0f, 0.0f)
		, MTL::PackedFloat3(0.0f, 1.0f, 0.0f)
		, MTL::PackedFloat3(0.0f, 0.0f, 1.0f)
		, MTL::PackedFloat3(0.0f, 0.0f, translateZ)
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

// The slang_RTSbt of the runtime contract: visible-function-table region bases
// plus the per-instance hit-group contributions (a device address).
struct SlangRTSbt
{
	uint32_t missBase;
	uint32_t hitBase;
	uint32_t callableBase;
	uint32_t hitStride;
	uint64_t instanceSbtOffsets;
};
static_assert(sizeof(SlangRTSbt) == 24, "must match the MSL layout");
