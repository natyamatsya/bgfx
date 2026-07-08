// Referee half of the Metal RT-pipeline P0 end-to-end: runs the SAME Slang sources
// (tools/rt-validation/p0/rt_p0_*.slang) through bgfx's Vulkan ray-tracing pipeline on
// lavapipe, so the Slang-native-Metal result (metal_rt_pipeline_p0) has a reference
// implementation to agree with. Expected: every pixel exactly 1.0 on both.
// Usage: rt_pipeline_p0_referee <rg.bin> <miss0.bin> <miss1.bin> <chit.bin>
#include <bgfx/bgfx.h>
#include <cstdio>
#include <cstdint>
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
	if (argc < 5) { printf("usage: %s <rg.bin> <miss0.bin> <miss1.bin> <chit.bin>\n", argv[0]); return 1; }
	const uint32_t kW = 64, kH = 64;

	bgfx::renderFrame();
	bgfx::Init init;
	init.type = bgfx::RendererType::Count;
	init.resolution.width = 0; init.resolution.height = 0;
	if (!bgfx::init(init) ) { printf("bgfx::init failed\n"); return 1; }

	const bool rtp = 0 != (bgfx::getCaps()->supported & BGFX_CAPS_RAY_TRACING_PIPELINE);
	printf("renderer: %s  ray_tracing_pipeline_cap=%d\n", bgfx::getRendererName(bgfx::getCaps()->rendererType), rtp);
	if (!rtp) { printf("RESULT: SKIP\n"); bgfx::shutdown(); return 0; }

	// Same scene as the Metal host: one triangle at z=5 straddling the +Z axis.
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

	bgfx::ShaderHandle rg = bgfx::createShader(loadBin(argv[1]) );
	bgfx::ShaderHandle mi[2] = { bgfx::createShader(loadBin(argv[2]) ), bgfx::createShader(loadBin(argv[3]) ) };
	bgfx::ShaderHandle ch = bgfx::createShader(loadBin(argv[4]) );
	bgfx::ProgramHandle prog = bgfx::createRtProgram(rg, mi, 2, &ch, NULL, NULL, 1, NULL, 0, true);
	printf("rt program valid=%d\n", bgfx::isValid(prog) );
	if (!bgfx::isValid(prog) ) { bgfx::shutdown(); return 1; }

	bgfx::TextureHandle outTex = bgfx::createTexture2D(uint16_t(kW), uint16_t(kH), false, 1, bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_COMPUTE_WRITE);
	bgfx::TextureHandle rbTex  = bgfx::createTexture2D(uint16_t(kW), uint16_t(kH), false, 1, bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_BLIT_DST | BGFX_TEXTURE_READ_BACK);

	bgfx::setAccelerationStructure(0, tlas);
	bgfx::setImage(1, outTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::dispatch(0, prog, kW, kH, 1);
	bgfx::blit(1, rbTex, 0, 0, outTex);

	std::vector<uint8_t> pixels(kW*kH*4, 0);
	uint32_t frameAvail = bgfx::readTexture(rbTex, pixels.data() );
	uint32_t frame = 0;
	while (frame < frameAvail) { frame = bgfx::frame(); }

	uint32_t full = 0;
	for (uint32_t i = 0; i < kW*kH; ++i) { if (pixels[i*4] >= 253) ++full; }
	printf("vulkan P0 pipeline: %u / %u pixels at 1.0   center=%u\n", full, kW*kH, pixels[(kH/2*kW + kW/2)*4]);
	const bool pass = full > (kW*kH - 8);
	printf(pass ? "RESULT: PASS\n" : "RESULT: FAIL\n");

	bgfx::destroy(tlas); bgfx::destroy(blas);
	bgfx::destroy(rbTex); bgfx::destroy(outTex);
	bgfx::destroy(prog); bgfx::destroy(vbh); bgfx::destroy(ibh);
	bgfx::shutdown();
	return pass ? 0 : 3;
}
