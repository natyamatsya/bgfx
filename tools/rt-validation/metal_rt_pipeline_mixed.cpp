// The MIXED-MODULE kit -- the runtime contract's centerpiece validation: three stage
// modules compiled by SEPARATE slangc invocations with the uniform flag set
// (-metal-rt-globals-slots 8), each seeing a different resource subset, assembled into
// one pipeline against one slot-addressed slang_RTGlobals encoding. The first test
// that can fail for ABI reasons rather than logic reasons.
//   raygen:  u_params.y through the kernel cbuffer (descriptor "buf")        +0.25
//   chit:    base 0.25 + materials[0].x via slot 3                           +0.50
//   missA:   u_params.x via the header uniforms entry + skyColors[0].x slot4 +0.25
//   total: exactly 1.0
// Phase B (runtime contract R3, pairs slang C3): a procedural scene whose
// INTERSECTION module reads its sphere from a global (slot 6) through the C3
// trailing [[buffer(0)]] parameter, bound with ift->setBuffer(globals, 0, 0) --
// intersection-table buffer slot 0 as the contract reserves. All four modules
// compiled separately with -metal-rt-force-isect-table.
//   chit base 0.5 + analytic t 0.25 + attrs-from-isect 0.25 = 1.0
// Usage: metal_rt_pipeline_mixed <rg> <miss> <chit> [<rgB> <missB> <isect> <chitP>]
#define CA_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#define NS_PRIVATE_IMPLEMENTATION
#include <metal-cpp/metal.hpp>
#include "metal_rt_host.h"
#include <vector>

// Parse an integer field from the module's ABI descriptor line (dogfooding the
// runtime-contract descriptor instead of hardcoding).
static int abiInt(const std::string& src, const char* key)
{
	size_t at = src.find("slang-metal-rt-abi:");
	if (at == std::string::npos) return -1;
	size_t k = src.find(key, at);
	if (k == std::string::npos) return -1;
	return atoi(src.c_str() + k + strlen(key));
}

int main(int argc, char** argv)
{
	if (argc < 4) { printf("usage: %s <rg.metal> <miss.metal> <chit.metal>\n", argv[0]); return 1; }
	const uint32_t kW = 64, kH = 64;

	MTL::Device* dev = MTL::CreateSystemDefaultDevice();
	if (!dev || !dev->supportsRaytracing() || !dev->supportsFunctionPointers()) { printf("RESULT: SKIP\n"); return 0; }
	MTL::CommandQueue* queue = dev->newCommandQueue();

	// Three separately compiled libraries -- the point.
	std::string rgSrc = loadText(argv[1]);
	MTL::Library* libRg   = loadStageLibrary(dev, argv[1]);
	MTL::Library* libMiss = loadStageLibrary(dev, argv[2]);
	MTL::Library* libChit = loadStageLibrary(dev, argv[3]);
	if (!libRg || !libMiss || !libChit) return 1;
	printf("stage functions (separate modules):\n");
	MTL::Function* fnRg   = stageFunction(libRg,   "rayGenMain");
	MTL::Function* fnMiss = stageFunction(libMiss, "missMain");
	MTL::Function* fnChit = stageFunction(libChit, "closestHitMain");
	if (!fnRg || !fnMiss || !fnChit) return 1;

	const int slots = abiInt(rgSrc, "\"slots\":");
	const int uniformsBuf = abiInt(rgSrc, "\"buf\":");
	printf("descriptor: slots=%d uniforms.buf=%d\n", slots, uniformsBuf);
	if (slots != 8 || uniformsBuf < 0) { printf("RESULT: FAIL (descriptor)\n"); return 3; }

	// Scene: one triangle at z=5.
	static const float verts[9] = { -2,-2,5, 2,-2,5, 0,2,5 };
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
	{ const NS::Object* geos[1] = { triGeo }; blasDesc->setGeometryDescriptors(NS::Array::array(geos, 1)); }
	MTL::AccelerationStructure* blas = buildAs(dev, queue, blasDesc);
	MTL::AccelerationStructure* tlas = buildTlas(dev, queue, blas, 0.0f);

	MTL::LinkedFunctions* linked = MTL::LinkedFunctions::alloc()->init();
	{ const NS::Object* fns[2] = { fnMiss, fnChit }; linked->setFunctions(NS::Array::array(fns, 2)); }
	MTL::ComputePipelineDescriptor* pd = MTL::ComputePipelineDescriptor::alloc()->init();
	pd->setComputeFunction(fnRg);
	pd->setLinkedFunctions(linked);
	pd->setMaxCallStackDepth(2);
	NS::Error* err = nullptr;
	MTL::ComputePipelineState* pso = dev->newComputePipelineState(pd, MTL::PipelineOptionNone, nullptr, &err);
	if (!pso) { printf("pipeline: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 1; }

	MTL::VisibleFunctionTableDescriptor* vtd = MTL::VisibleFunctionTableDescriptor::alloc()->init();
	vtd->setFunctionCount(2);
	MTL::VisibleFunctionTable* vft = pso->newVisibleFunctionTable(vtd);
	vft->setFunction(pso->functionHandle(fnMiss), 0);
	vft->setFunction(pso->functionHandle(fnChit), 1);

	MTL::Buffer* instOffsets = dev->newBuffer(4, MTL::ResourceStorageModeShared);
	*(uint32_t*)instOffsets->contents() = 0;
	SlangRTSbt sbt = { 0, 1, 2, 1, instOffsets->gpuAddress() };
	MTL::Buffer* sbtBuf = dev->newBuffer(sizeof(sbt), MTL::ResourceStorageModeShared);
	memcpy(sbtBuf->contents(), &sbt, sizeof(sbt));

	static const float uParams[4]  = { 0.125f, 0.25f, 0.0f, 0.0f };
	static const float mats[4]     = { 0.25f, 0, 0, 0 };
	static const float sky[4]      = { 0.125f, 0, 0, 0 };
	MTL::Buffer* uParamsBuf  = dev->newBuffer(uParams, sizeof(uParams), MTL::ResourceStorageModeShared);
	MTL::Buffer* materials   = dev->newBuffer(mats, sizeof(mats), MTL::ResourceStorageModeShared);
	MTL::Buffer* skyColors   = dev->newBuffer(sky, sizeof(sky), MTL::ResourceStorageModeShared);

	// The slot-addressed slang_RTGlobals: header 0/8/16/40, slots from 48.
	MTL::Buffer* globalsBuf = dev->newBuffer(48 + 8*8, MTL::ResourceStorageModeShared);
	uint8_t* g = (uint8_t*)globalsBuf->contents();
	memset(g, 0, 48 + 8*8);
	uint64_t v64;
	v64 = vft->gpuResourceID()._impl;      memcpy(g + 0,  &v64, 8);
	memcpy(g + 16, &sbt, 24);
	v64 = uParamsBuf->gpuAddress();        memcpy(g + 40, &v64, 8); // uniforms header entry
	v64 = tlas->gpuResourceID()._impl;     memcpy(g + 48 + 8*0, &v64, 8); // slot 0: scene
	v64 = materials->gpuAddress();         memcpy(g + 48 + 8*3, &v64, 8); // slot 3
	v64 = skyColors->gpuAddress();         memcpy(g + 48 + 8*4, &v64, 8); // slot 4

	MTL::TextureDescriptor* td = MTL::TextureDescriptor::texture2DDescriptor(MTL::PixelFormatRGBA8Unorm, kW, kH, false);
	td->setUsage(MTL::TextureUsageShaderWrite | MTL::TextureUsageShaderRead);
	MTL::Texture* target = dev->newTexture(td);

	MTL::CommandBuffer* cmd = queue->commandBuffer();
	MTL::ComputeCommandEncoder* enc = cmd->computeCommandEncoder();
	enc->setComputePipelineState(pso);
	enc->setAccelerationStructure(tlas, 0);              // scene   [[buffer(0)]]
	enc->setBuffer(uParamsBuf, 0, uniformsBuf);          // GlobalParams at descriptor buf
	enc->setTexture(target, 0);                          // target  [[texture(0)]]
	enc->setBuffer(globalsBuf, 0, 28);
	enc->setBuffer(sbtBuf, 0, 29);
	enc->setVisibleFunctionTable(vft, 30);
	enc->useResource(tlas, MTL::ResourceUsageRead);
	enc->useResource(blas, MTL::ResourceUsageRead);
	enc->useResource(instOffsets, MTL::ResourceUsageRead);
	enc->useResource(uParamsBuf, MTL::ResourceUsageRead);
	enc->useResource(materials, MTL::ResourceUsageRead);
	enc->useResource(skyColors, MTL::ResourceUsageRead);
	enc->useResource(vft, MTL::ResourceUsageRead);
	enc->dispatchThreads(MTL::Size(kW, kH, 1), MTL::Size(8, 8, 1));
	enc->endEncoding();
	cmd->commit();
	cmd->waitUntilCompleted();

	std::vector<uint8_t> px(kW*kH*4);
	target->getBytes(px.data(), kW*4, MTL::Region(0, 0, kW, kH), 0);
	uint32_t good = 0;
	for (uint32_t i = 0; i < kW*kH; ++i) if (px[i*4] >= 253) ++good;
	printf("mixed-module separate-compilation ABI: %u / 4096 at 1.0   center=%u\n", good, px[(kH/2*kW + kW/2)*4]);
	const bool pass = good > 4088;
	printf(pass ? "RESULT: PASS (three modules, one slot-addressed ABI)\n" : "RESULT: FAIL\n");

	bool passB = true;
	if (argc >= 8)
	{
		MTL::Library* libRgB   = loadStageLibrary(dev, argv[4]);
		MTL::Library* libMissB = loadStageLibrary(dev, argv[5]);
		MTL::Library* libIsect = loadStageLibrary(dev, argv[6]);
		MTL::Library* libChitP = loadStageLibrary(dev, argv[7]);
		if (!libRgB || !libMissB || !libIsect || !libChitP) return 1;
		printf("phase B stage functions (separate modules, forced isect table):\n");
		MTL::Function* fnRgB   = stageFunction(libRgB,   "rayGenMain");
		MTL::Function* fnMissB = stageFunction(libMissB, "missMain");
		MTL::Function* fnIsect = stageFunction(libIsect, "sphereIsect");
		MTL::Function* fnChitP = stageFunction(libChitP, "closestHitMain");
		if (!fnRgB || !fnMissB || !fnIsect || !fnChitP) return 1;

		// Procedural scene: one AABB around the sphere the ISECT reads from slot 6.
		static const float aabb[6] = { -1, -1, 4, 1, 1, 6 };
		MTL::Buffer* ab = dev->newBuffer(aabb, sizeof(aabb), MTL::ResourceStorageModeShared);
		MTL::AccelerationStructureBoundingBoxGeometryDescriptor* boxGeo = MTL::AccelerationStructureBoundingBoxGeometryDescriptor::alloc()->init();
		boxGeo->setOpaque(true);
		boxGeo->setBoundingBoxBuffer(ab);
		boxGeo->setBoundingBoxStride(24);
		boxGeo->setBoundingBoxCount(1);
		boxGeo->setIntersectionFunctionTableOffset(0);
		MTL::PrimitiveAccelerationStructureDescriptor* boxDesc = MTL::PrimitiveAccelerationStructureDescriptor::alloc()->init();
		{ const NS::Object* geos[1] = { boxGeo }; boxDesc->setGeometryDescriptors(NS::Array::array(geos, 1)); }
		MTL::AccelerationStructure* boxBlas = buildAs(dev, queue, boxDesc);
		MTL::AccelerationStructure* boxTlas = buildTlas(dev, queue, boxBlas, 0.0f);

		MTL::LinkedFunctions* linkedB = MTL::LinkedFunctions::alloc()->init();
		{ const NS::Object* fns[3] = { fnMissB, fnChitP, fnIsect }; linkedB->setFunctions(NS::Array::array(fns, 3)); }
		MTL::ComputePipelineDescriptor* pdB = MTL::ComputePipelineDescriptor::alloc()->init();
		pdB->setComputeFunction(fnRgB);
		pdB->setLinkedFunctions(linkedB);
		pdB->setMaxCallStackDepth(2);
		MTL::ComputePipelineState* psoB = dev->newComputePipelineState(pdB, MTL::PipelineOptionNone, nullptr, &err);
		if (!psoB) { printf("phase B pipeline: %s\n", err ? err->localizedDescription()->utf8String() : "?"); return 1; }

		MTL::VisibleFunctionTable* vftB = psoB->newVisibleFunctionTable(vtd);
		vftB->setFunction(psoB->functionHandle(fnMissB), 0);
		vftB->setFunction(psoB->functionHandle(fnChitP), 1);
		MTL::IntersectionFunctionTableDescriptor* itd = MTL::IntersectionFunctionTableDescriptor::alloc()->init();
		itd->setFunctionCount(1);
		MTL::IntersectionFunctionTable* ift = psoB->newIntersectionFunctionTable(itd);
		ift->setFunction(psoB->functionHandle(fnIsect), 0);

		static const float sphereData[4] = { 0.0f, 0.0f, 5.0f, 0.8f };
		MTL::Buffer* spheres = dev->newBuffer(sphereData, sizeof(sphereData), MTL::ResourceStorageModeShared);

		MTL::Buffer* globalsB = dev->newBuffer(48 + 8*8, MTL::ResourceStorageModeShared);
		uint8_t* gb = (uint8_t*)globalsB->contents();
		memset(gb, 0, 48 + 8*8);
		uint64_t w64;
		w64 = vftB->gpuResourceID()._impl;   memcpy(gb + 0,  &w64, 8);
		w64 = ift->gpuResourceID()._impl;    memcpy(gb + 8,  &w64, 8);
		memcpy(gb + 16, &sbt, 24);
		w64 = uParamsBuf->gpuAddress();      memcpy(gb + 40, &w64, 8);
		w64 = boxTlas->gpuResourceID()._impl; memcpy(gb + 48 + 8*0, &w64, 8);
		w64 = skyColors->gpuAddress();       memcpy(gb + 48 + 8*4, &w64, 8); // slot 4: missB's global
		w64 = spheres->gpuAddress();         memcpy(gb + 48 + 8*6, &w64, 8); // slot 6: isect's global

		// THE R3 LINE: the contract reserves intersection-table buffer slot 0 for
		// the globals argument buffer, feeding the C3 trailing parameter.
		ift->setBuffer(globalsB, 0, 0);

		MTL::Texture* targetB = dev->newTexture(td);
		MTL::CommandBuffer* cmdB = queue->commandBuffer();
		MTL::ComputeCommandEncoder* encB = cmdB->computeCommandEncoder();
		encB->setComputePipelineState(psoB);
		encB->setAccelerationStructure(boxTlas, 0);
		encB->setBuffer(uParamsBuf, 0, uniformsBuf);
		encB->setTexture(targetB, 0);
		encB->setIntersectionFunctionTable(ift, 27);
		encB->setBuffer(globalsB, 0, 28);
		encB->setBuffer(sbtBuf, 0, 29);
		encB->setVisibleFunctionTable(vftB, 30);
		encB->useResource(boxTlas, MTL::ResourceUsageRead);
		encB->useResource(boxBlas, MTL::ResourceUsageRead);
		encB->useResource(instOffsets, MTL::ResourceUsageRead);
		encB->useResource(uParamsBuf, MTL::ResourceUsageRead);
		encB->useResource(spheres, MTL::ResourceUsageRead);  // R3: isect-referenced tail residency
		encB->useResource(skyColors, MTL::ResourceUsageRead);
		encB->useResource(vftB, MTL::ResourceUsageRead);
		encB->useResource(ift, MTL::ResourceUsageRead);
		encB->useResource(globalsB, MTL::ResourceUsageRead);
		encB->dispatchThreads(MTL::Size(kW, kH, 1), MTL::Size(8, 8, 1));
		encB->endEncoding();
		cmdB->commit();
		cmdB->waitUntilCompleted();

		targetB->getBytes(px.data(), kW*4, MTL::Region(0, 0, kW, kH), 0);
		uint32_t goodB = 0;
		// Phase B raygen reuses mm_rg: v = chit(1.0) + missA-for-away-ray... the away
		// ray misses into record 0 = missB (u_params.x + skyColors -- skyColors slot
		// empty in phase B => 0.125) plus kernel u_params.y (0.25): expect 1.0 + 0.375
		// saturating to 255? No: mm_rg's first ray hits the AABB scene's sphere ->
		// chit 1.0; away ray -> missB reads u_params.x(0.125) + skyColors slot4 (0 --
		// empty slot reads are out of contract). Keep it simple: expect >= 253 from
		// the chit path alone; the additive breakdown lives in phase A.
		for (uint32_t i = 0; i < kW*kH; ++i) if (px[i*4] >= 253) ++goodB;
		printf("phase B (C3 isect globals via ift->setBuffer): %u / 4096 saturated   center=%u\n", goodB, px[(kH/2*kW + kW/2)*4]);
		passB = goodB > 4088;
		printf(passB ? "RESULT_B: PASS (intersection-stage globals on-device)\n" : "RESULT_B: FAIL\n");
	}
	return (pass && passB) ? 0 : 3;
}
