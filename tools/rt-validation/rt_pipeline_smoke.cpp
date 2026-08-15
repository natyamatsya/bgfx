// Headless ray-tracing PIPELINE smoke test: build a triangle BLAS/TLAS, create a
// raygen+miss+closesthit program (bgfx::createRtProgram), trace one ray per pixel with
// bgfx::dispatch (ray-grid dimensions in rays), read back the image. Expect white (hit).
// Skips cleanly (exit 0) where BGFX_CAPS_RAY_TRACING_PIPELINE is absent. All three phases
// run on Vulkan, D3D12 and Metal; compile the stage shaders for the target in question.
// Usage: rt_pipeline_smoke <rg> <miss> <miss2> <chit> <rg2> <ahit> <chit2> <callable> <isect> <chit3>
#include <bgfx/bgfx.h>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

static const bgfx::Memory* loadBin(const char* path)
{
	FILE* f = fopen(path, "rb");
	if (!f) { printf("cannot open %s\n", path); return nullptr; }
	fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
	const bgfx::Memory* mem = bgfx::alloc(uint32_t(n));
	if (fread(mem->data, 1, n, f) != size_t(n)) { fclose(f); return nullptr; }
	fclose(f);
	return mem;
}

int main(int argc, char** argv)
{
	if (argc < 11) { printf("usage: %s <rg> <miss> <miss2> <chit> <rg2> <ahit> <chit2> <callable> <isect> <chit3>\n", argv[0]); return 1; }
	const uint32_t kW = 64, kH = 64;

	bgfx::renderFrame();
	bgfx::Init init;
	init.type = bgfx::RendererType::Count;
	// Optional Windows/CI overrides (default: auto-select). BGFX_RT_RENDERER forces the
	// backend ("d3d12"/"vulkan"/"d3d11"); BGFX_RT_WARP=1 picks the software adapter (WARP on
	// D3D12); BGFX_RT_DEBUG=1 enables the debug layer.
	if (const char* r = getenv("BGFX_RT_RENDERER") )
	{
		if      (0 == strcmp(r, "d3d12")  || 0 == strcmp(r, "direct3d12") ) init.type = bgfx::RendererType::Direct3D12;
		else if (0 == strcmp(r, "vulkan") || 0 == strcmp(r, "vk") )         init.type = bgfx::RendererType::Vulkan;
		else if (0 == strcmp(r, "d3d11")  || 0 == strcmp(r, "direct3d11") ) init.type = bgfx::RendererType::Direct3D11;
	}
	if (NULL != getenv("BGFX_RT_WARP") )  { init.vendorId = BGFX_PCI_ID_SOFTWARE_RASTERIZER; }
	if (NULL != getenv("BGFX_RT_DEBUG") ) { init.debug = true; }
	init.resolution.width = 0; init.resolution.height = 0;
	if (!bgfx::init(init) ) { printf("bgfx::init failed\n"); return 1; }

	const bgfx::Caps* caps = bgfx::getCaps();
	const bool rtp = 0 != (caps->supported & BGFX_CAPS_RAY_TRACING_PIPELINE);
	printf("renderer: %s  ray_tracing_pipeline_cap=%d\n", bgfx::getRendererName(caps->rendererType), rtp);
	if (!rtp) { printf("RESULT: SKIP (ray-tracing pipelines not supported on this backend)\n"); bgfx::shutdown(); return 0; }

	// Triangle at z=5 spanning the +Z axis; the ray (0,0,0)->(0,0,1) hits its interior.
	struct Vert { float x, y, z; };
	static const Vert verts[3] = { {-2,-2,5}, {2,-2,5}, {0,2,5} };
	static const uint16_t indices[3] = { 0, 1, 2 };

	bgfx::VertexLayout layout;
	layout.begin().add(bgfx::Attrib::Position, 3, bgfx::AttribType::Float).end();

	bgfx::VertexBufferHandle vbh = bgfx::createVertexBuffer(bgfx::copy(verts, sizeof(verts) ), layout);
	bgfx::IndexBufferHandle  ibh = bgfx::createIndexBuffer (bgfx::copy(indices, sizeof(indices) ) );

	bgfx::AccelerationStructureHandle blas = bgfx::createBlas(&vbh, &ibh, 1);
	bgfx::AccelerationStructureHandle tlas = bgfx::createTlas(&blas, 1);
	bgfx::frame(); bgfx::frame();

	bgfx::ShaderHandle rg  = bgfx::createShader(loadBin(argv[1]) );
	bgfx::ShaderHandle mi[2] = { bgfx::createShader(loadBin(argv[2]) ), bgfx::createShader(loadBin(argv[3]) ) };
	bgfx::ShaderHandle ch  = bgfx::createShader(loadBin(argv[4]) );
	printf("shaders valid: rg=%d miss=%d miss2=%d chit=%d\n", bgfx::isValid(rg), bgfx::isValid(mi[0]), bgfx::isValid(mi[1]), bgfx::isValid(ch) );
	if (!bgfx::isValid(rg) || !bgfx::isValid(mi[0]) || !bgfx::isValid(mi[1]) || !bgfx::isValid(ch) ) { bgfx::shutdown(); return 1; }

	// Per-primitive material read by the closest-hit stage (a chit-only resource).
	bgfx::VertexLayout matLayout;
	matLayout.begin().add(bgfx::Attrib::TexCoord0, 1, bgfx::AttribType::Float).end();
	static const float mats[4] = { 0.75f, 0.75f, 0.75f, 0.75f };
	bgfx::VertexBufferHandle mbh = bgfx::createVertexBuffer(bgfx::copy(mats, sizeof(mats) ), matLayout, BGFX_BUFFER_COMPUTE_READ);

	bgfx::ProgramHandle prog = bgfx::createRtProgram(rg, mi, 2, &ch, NULL, NULL, 1, NULL, 0, true);
	printf("rt program valid=%d\n", bgfx::isValid(prog) );
	if (!bgfx::isValid(prog) ) { bgfx::shutdown(); return 1; }

	bgfx::TextureHandle outTex = bgfx::createTexture2D(uint16_t(kW), uint16_t(kH), false, 1, bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_COMPUTE_WRITE);
	bgfx::TextureHandle rbTex  = bgfx::createTexture2D(uint16_t(kW), uint16_t(kH), false, 1, bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_BLIT_DST | BGFX_TEXTURE_READ_BACK);

	// scene (accel structure) -> stage 0; s_target (image) -> stage 1. For a ray-tracing
	// program the dispatch dimensions are the ray-grid size in RAYS.
	bgfx::setAccelerationStructure(0, tlas);
	bgfx::setImage(1, outTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::setBuffer(2, mbh, bgfx::Access::Read); // chit-only material buffer
	bgfx::dispatch(0, prog, kW, kH, 1);
	bgfx::blit(1, rbTex, 0, 0, outTex);

	std::vector<uint8_t> pixels(kW*kH*4, 0);
	uint32_t frameAvail = bgfx::readTexture(rbTex, pixels.data() );
	uint32_t frame = 0;
	while (frame < frameAvail) { frame = bgfx::frame(); }

	// Payload 1.0 (white) requires the chit material read (0.75) AND the secondary ray
	// reaching miss index 1 (+0.25). ~191 = miss routing broken, ~63 = material broken.
	uint32_t hits = 0;
	for (uint32_t i = 0; i < kW*kH; ++i) { if (pixels[i*4] > 240) ++hits; }
	const uint32_t c = (kH/2*kW + kW/2)*4;
	printf("full-white pixels: %u / %u   center RGBA=(%u,%u,%u,%u)\n", hits, kW*kH, pixels[c],pixels[c+1],pixels[c+2],pixels[c+3]);
	const bool pass = hits > (kW*kH/2);
	printf(pass ? "RESULT: PASS (chit resource + multi-miss + recursion)\n" : "RESULT: FAIL\n");

	// Phase 2: any-hit + callable. Two instances of the same triangle BLAS, one in front
	// of the other; the any-hit stage rejects hits on the front instance and the
	// closest-hit shader adds a callable's contribution to the back instance's material.
	bgfx::AccelerationStructureHandle blases2[2] = { blas, blas };
	bgfx::AccelerationStructureHandle tlas2 = bgfx::createTlas(blases2, 2);
	float xf[32] = {};
	xf[0] = xf[5] = xf[10] = xf[15] = 1.0f; xf[14] = -2.0f;   // instance 0: triangle at z=3
	xf[16] = xf[21] = xf[26] = xf[31] = 1.0f;                 // instance 1: identity (z=5)
	bgfx::updateTlas(tlas2, bgfx::copy(xf, sizeof(xf) ) );
	bgfx::frame(); bgfx::frame();

	bgfx::ShaderHandle rg2  = bgfx::createShader(loadBin(argv[5]) );
	bgfx::ShaderHandle ah   = bgfx::createShader(loadBin(argv[6]) );
	bgfx::ShaderHandle ch2  = bgfx::createShader(loadBin(argv[7]) );
	bgfx::ShaderHandle call = bgfx::createShader(loadBin(argv[8]) );
	bgfx::ShaderHandle mi2b = bgfx::createShader(loadBin(argv[2]) ); // reuse miss 0
	printf("phase2 shaders valid: rg2=%d ahit=%d chit2=%d call=%d\n", bgfx::isValid(rg2), bgfx::isValid(ah), bgfx::isValid(ch2), bgfx::isValid(call) );

	bgfx::VertexLayout mat2Layout;
	mat2Layout.begin().add(bgfx::Attrib::TexCoord0, 1, bgfx::AttribType::Float).end();
	static const float mats2[4] = { 0.25f, 0.5f, 0.0f, 0.0f }; // per-instance
	bgfx::VertexBufferHandle mbh2 = bgfx::createVertexBuffer(bgfx::copy(mats2, sizeof(mats2) ), mat2Layout, BGFX_BUFFER_COMPUTE_READ);

	bgfx::ProgramHandle prog2 = bgfx::createRtProgram(rg2, &mi2b, 1, &ch2, &ah, NULL, 1, &call, 1, true);
	printf("phase2 rt program valid=%d\n", bgfx::isValid(prog2) );

	bgfx::setAccelerationStructure(0, tlas2);
	bgfx::setImage(1, outTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::setBuffer(2, mbh2, bgfx::Access::Read);
	bgfx::dispatch(0, prog2, kW, kH, 1);
	bgfx::blit(1, rbTex, 0, 0, outTex);
	frameAvail = bgfx::readTexture(rbTex, pixels.data() );
	while (frame < frameAvail) { frame = bgfx::frame(); }

	// 1.0 needs any-hit (back-instance material 0.5) AND the callable (+0.5);
	// ~191 = any-hit broken (front instance 0.25 + 0.5), ~128 = callable broken.
	uint32_t hits2 = 0;
	for (uint32_t i = 0; i < kW*kH; ++i) { if (pixels[i*4] > 240) ++hits2; }
	printf("phase2 full-white pixels: %u / %u   center=%u\n", hits2, kW*kH, pixels[(kH/2*kW + kW/2)*4]);
	const bool pass2 = hits2 > (kW*kH/2);
	printf(pass2 ? "RESULT2: PASS (anyhit + callable)\n" : "RESULT2: FAIL\n");

	bgfx::destroy(prog2); bgfx::destroy(mbh2); bgfx::destroy(tlas2);

	// Phase 3: procedural intersection. A sphere (centre (0,0,5), r=0.8) lives inside a
	// single AABB BLAS geometry; the intersection shader reports the analytic entry point
	// and the closest-hit shader validates the reported t (0.5 hit + 0.5 t-check).
	bgfx::VertexLayout aabbLayout;
	aabbLayout.begin()
		.add(bgfx::Attrib::TexCoord0, 3, bgfx::AttribType::Float)
		.add(bgfx::Attrib::TexCoord1, 3, bgfx::AttribType::Float)
		.end(); // 24-byte stride: min xyz, max xyz
	static const float aabb[6] = { -1.0f, -1.0f, 4.0f, 1.0f, 1.0f, 6.0f };
	bgfx::VertexBufferHandle abh = bgfx::createVertexBuffer(bgfx::copy(aabb, sizeof(aabb) ), aabbLayout);

	bgfx::AccelerationStructureHandle blas3 = bgfx::createBlasAabbs(&abh, 1);
	bgfx::AccelerationStructureHandle tlas3 = bgfx::createTlas(&blas3, 1);
	bgfx::frame(); bgfx::frame();

	bgfx::ShaderHandle rg3  = bgfx::createShader(loadBin(argv[1]) ); // reuse plain raygen
	bgfx::ShaderHandle mi3  = bgfx::createShader(loadBin(argv[2]) ); // reuse miss 0
	bgfx::ShaderHandle is3  = bgfx::createShader(loadBin(argv[9]) );
	bgfx::ShaderHandle ch3  = bgfx::createShader(loadBin(argv[10]) );
	printf("phase3 shaders valid: rg=%d miss=%d isect=%d chit3=%d\n", bgfx::isValid(rg3), bgfx::isValid(mi3), bgfx::isValid(is3), bgfx::isValid(ch3) );

	bgfx::ProgramHandle prog3 = bgfx::createRtProgram(rg3, &mi3, 1, &ch3, NULL, &is3, 1, NULL, 0, true);
	printf("phase3 rt program valid=%d\n", bgfx::isValid(prog3) );

	bgfx::setAccelerationStructure(0, tlas3);
	bgfx::setImage(1, outTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::dispatch(0, prog3, kW, kH, 1);
	bgfx::blit(1, rbTex, 0, 0, outTex);
	frameAvail = bgfx::readTexture(rbTex, pixels.data() );
	while (frame < frameAvail) { frame = bgfx::frame(); }

	// 1.0 needs the procedural hit (0.5) AND the reported t to equal the analytic sphere
	// entry 4.2 (+0.5); ~128 = hit with wrong t, 0 = intersection stage never ran.
	uint32_t hits3 = 0;
	for (uint32_t i = 0; i < kW*kH; ++i) { if (pixels[i*4] > 240) ++hits3; }
	printf("phase3 full-white pixels: %u / %u   center=%u\n", hits3, kW*kH, pixels[(kH/2*kW + kW/2)*4]);
	const bool pass3 = hits3 > (kW*kH/2);
	printf(pass3 ? "RESULT3: PASS (procedural intersection)\n" : "RESULT3: FAIL\n");

	bgfx::destroy(prog3); bgfx::destroy(tlas3); bgfx::destroy(blas3); bgfx::destroy(abh);

	bgfx::destroy(tlas); bgfx::destroy(blas);
	bgfx::destroy(rbTex); bgfx::destroy(outTex);
	bgfx::destroy(prog); bgfx::destroy(mbh); bgfx::destroy(vbh); bgfx::destroy(ibh);
	bgfx::shutdown();
	return (pass && pass2 && pass3) ? 0 : 3;
}
