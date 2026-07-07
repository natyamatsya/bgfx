// Headless ray-tracing PIPELINE smoke test: build a triangle BLAS/TLAS, create a
// raygen+miss+closesthit program (bgfx::createRtProgram), trace one ray per pixel with
// bgfx::dispatch (ray-grid dimensions in rays), read back the image. Expect white (hit).
// Skips cleanly (exit 0) where BGFX_CAPS_RAY_TRACING_PIPELINE is absent (e.g. Metal).
// Usage: rt_pipeline_smoke <raygen.bin> <miss.bin> <miss2.bin> <closesthit.bin>
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
	if (argc < 5) { printf("usage: %s <raygen.bin> <miss.bin> <miss2.bin> <closesthit.bin>\n", argv[0]); return 1; }
	const uint32_t kW = 64, kH = 64;

	bgfx::renderFrame();
	bgfx::Init init;
	init.type = bgfx::RendererType::Count;
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

	bgfx::ProgramHandle prog = bgfx::createRtProgram(rg, mi, 2, &ch, 1, true);
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

	bgfx::destroy(tlas); bgfx::destroy(blas);
	bgfx::destroy(rbTex); bgfx::destroy(outTex);
	bgfx::destroy(prog); bgfx::destroy(mbh); bgfx::destroy(vbh); bgfx::destroy(ibh);
	bgfx::shutdown();
	return pass ? 0 : 3;
}
