// Headless end-to-end ray-query test: build a triangle BLAS+TLAS, trace one ray per pixel
// (all pixels trace the same ray straight down +Z into the triangle), read back the image.
// Expect white (hit). Proves createBlas/createTlas + setAccelerationStructure + ray query
// on the Metal backend. Usage: rt_run <rq.bin>
#include <bgfx/bgfx.h>
#include <cmath>
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
	if (argc < 2) { printf("usage: %s <rq.bin>\n", argv[0]); return 1; }
	const uint32_t kW = 64, kH = 64;

	bgfx::renderFrame();
	bgfx::Init init;
	init.type = bgfx::RendererType::Count;
	init.resolution.width = 0; init.resolution.height = 0;
	if (!bgfx::init(init) ) { printf("bgfx::init failed\n"); return 1; }

	const bgfx::Caps* caps = bgfx::getCaps();
	const bool rt = 0 != (caps->supported & BGFX_CAPS_RAY_TRACING);
	printf("renderer: %s  ray_tracing_cap=%d\n", bgfx::getRendererName(caps->rendererType), rt);
	if (!rt) { printf("BGFX_CAPS_RAY_TRACING not supported; cannot run.\n"); bgfx::shutdown(); return 2; }

	// Triangle at z=5 spanning the +Z axis; the ray (0,0,0)->(0,0,1) hits its interior.
	struct Vert { float x, y, z; };
	static const Vert verts[3] = { {-2,-2,5}, {2,-2,5}, {0,2,5} };
	static const uint16_t indices[3] = { 0, 1, 2 };

	bgfx::VertexLayout layout;
	layout.begin().add(bgfx::Attrib::Position, 3, bgfx::AttribType::Float).end();

	bgfx::VertexBufferHandle vbh = bgfx::createVertexBuffer(bgfx::copy(verts, sizeof(verts) ), layout);
	bgfx::IndexBufferHandle  ibh = bgfx::createIndexBuffer (bgfx::copy(indices, sizeof(indices) ) );

	bgfx::AccelerationStructureHandle blas = bgfx::createBlas(vbh, ibh);
	bgfx::AccelerationStructureHandle tlas = bgfx::createTlas(&blas, 1);
	printf("blas valid=%d tlas valid=%d\n", bgfx::isValid(blas), bgfx::isValid(tlas) );

	// Flush a couple of frames so the acceleration-structure builds complete before the
	// ray-query dispatch reads them.
	bgfx::frame();
	bgfx::frame();

	const bgfx::Memory* mem = loadBin(argv[1]);
	if (!mem) { bgfx::shutdown(); return 1; }
	bgfx::ShaderHandle csh = bgfx::createShader(mem);
	if (!bgfx::isValid(csh) ) { printf("createShader failed\n"); bgfx::shutdown(); return 1; }
	bgfx::ProgramHandle prog = bgfx::createProgram(csh, true);
	if (!bgfx::isValid(prog) ) { printf("createProgram failed\n"); bgfx::shutdown(); return 1; }

	bgfx::TextureHandle outTex = bgfx::createTexture2D(uint16_t(kW), uint16_t(kH), false, 1, bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_COMPUTE_WRITE);
	bgfx::TextureHandle rbTex  = bgfx::createTexture2D(uint16_t(kW), uint16_t(kH), false, 1, bgfx::TextureFormat::RGBA8, BGFX_TEXTURE_BLIT_DST | BGFX_TEXTURE_READ_BACK);

	// scene (accel structure) -> stage 0; s_target (image) -> stage 1.
	bgfx::setAccelerationStructure(0, tlas);
	bgfx::setImage(1, outTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::dispatch(0, prog, kW/8, kH/8, 1);
	bgfx::blit(1, rbTex, 0, 0, outTex);

	std::vector<uint8_t> pixels(kW*kH*4, 0);
	uint32_t frameAvail = bgfx::readTexture(rbTex, pixels.data() );
	uint32_t frame = 0;
	while (frame < frameAvail) { frame = bgfx::frame(); }

	// All threads trace the same ray, so the image is uniform. Count white (hit) pixels.
	uint32_t hits = 0;
	for (uint32_t i = 0; i < kW*kH; ++i) { if (pixels[i*4] > 127) ++hits; }
	const uint32_t c = (kH/2*kW + kW/2)*4;
	printf("hit pixels: %u / %u   center RGBA=(%u,%u,%u,%u)\n", hits, kW*kH, pixels[c],pixels[c+1],pixels[c+2],pixels[c+3]);
	printf(hits > (kW*kH/2) ? "RESULT: PASS (ray query hit the triangle)\n" : "RESULT: FAIL (no hit)\n");
	bool pass1 = hits > (kW*kH/2);

	// updateTlas test: rotate the instance 90 deg about Y -> the triangle leaves the ray's
	// path -> expect a miss.
	float mtx[16] = {};
	const float ang = 1.5707963f;
	mtx[0] = cosf(ang); mtx[2] = sinf(ang); mtx[5] = 1.0f; mtx[8] = -sinf(ang); mtx[10] = cosf(ang); mtx[15] = 1.0f;
	bgfx::updateTlas(tlas, bgfx::copy(mtx, sizeof(mtx)));
	bgfx::frame(); bgfx::frame();

	bgfx::setAccelerationStructure(0, tlas);
	bgfx::setImage(1, outTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
	bgfx::dispatch(0, prog, kW/8, kH/8, 1);
	bgfx::blit(1, rbTex, 0, 0, outTex);
	frameAvail = bgfx::readTexture(rbTex, pixels.data());
	while (frame < frameAvail) { frame = bgfx::frame(); }
	uint32_t hits2 = 0;
	for (uint32_t i = 0; i < kW*kH; ++i) { if (pixels[i*4] > 127) ++hits2; }
	printf("after updateTlas(rotY 90): hit pixels %u / %u\n", hits2, kW*kH);
	bool pass2 = hits2 < (kW*kH/10);
	printf(pass2 ? "RESULT2: PASS (rotated instance misses)\n" : "RESULT2: FAIL (still hitting)\n");

	bgfx::destroy(tlas); bgfx::destroy(blas);
	bgfx::destroy(rbTex); bgfx::destroy(outTex);
	bgfx::destroy(prog); bgfx::destroy(vbh); bgfx::destroy(ibh);
	bgfx::shutdown();
	return (pass1 && pass2) ? 0 : 3;
}
