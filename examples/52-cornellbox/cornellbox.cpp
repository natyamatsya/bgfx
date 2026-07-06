/*
 * Copyright 2011-2026 Branimir Karadzic. All rights reserved.
 * License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
 */

// Cornell Box path traced in a Slang shader.
//
// Two paths, selected at runtime:
//  - Hardware ray query (BGFX_CAPS_RAY_TRACING): the scene as three BLASes (walls+light,
//    tall box, short box) instanced by a TLAS built through the bgfx
//    acceleration-structure API, traced by inline ray query from a compute shader
//    (cs_cornellbox_rq.slang). The box instances rotate via bgfx::updateTlas.
//  - Compute fallback (BGFX_CAPS_COMPUTE only): a self-contained analytic path tracer
//    (cs_cornellbox.slang) with the same estimator and rotating OBBs.
// Both are progressive path tracers accumulating into an RGBA32F image; the running
// average is tonemapped into the display texture, which a fullscreen quad presents.
// Spacebar toggles the rotation mode (the accumulation restarts every frame while the
// boxes move -- 1 sample/pixel real time -- and converges again once they stop).

#include "common.h"
#include "bgfx_utils.h"
#include "imgui/imgui.h"
#include "entry/input.h"

#include <bx/math.h>

#include <vector>

namespace
{

// --- Cornell Box triangle mesh (for the hardware ray-query path) -----------------------
// The RT path traces real triangle meshes. Each triangle carries a material
// (albedo / emission / inward normal, in BLAS-local space) in a parallel buffer indexed by
// instance*12 + primitive; the shader reads it after a committed hit.

struct RtMaterial
{
	float m_albedo[4];
	float m_emission[4];
	float m_normal[4];
};

struct RtMesh
{
	std::vector<float>      m_positions; // xyz per vertex
	std::vector<uint16_t>   m_indices;
	std::vector<RtMaterial> m_materials; // one per triangle

	void quad(
		  const float a[3], const float b[3], const float c[3], const float d[3]
		, float nx, float ny, float nz
		, float r, float g, float bl
		, float er = 0.0f, float eg = 0.0f, float eb = 0.0f
		)
	{
		const uint16_t base = uint16_t(m_positions.size() / 3);
		const float* v[4] = { a, b, c, d };
		for (uint32_t ii = 0; ii < 4; ++ii)
		{
			m_positions.push_back(v[ii][0]);
			m_positions.push_back(v[ii][1]);
			m_positions.push_back(v[ii][2]);
		}
		const uint16_t tri[6] = { base, uint16_t(base+1), uint16_t(base+2), base, uint16_t(base+2), uint16_t(base+3) };
		for (uint32_t ii = 0; ii < 6; ++ii) m_indices.push_back(tri[ii]);

		RtMaterial m = { { r, g, bl, 0.0f }, { er, eg, eb, 0.0f }, { nx, ny, nz, 0.0f } };
		m_materials.push_back(m); // two triangles, same material
		m_materials.push_back(m);
	}

	// Axis-aligned box [lo,hi] with outward-facing normals (6 quads = 12 triangles).
	void box(const float lo[3], const float hi[3], float r, float g, float bl)
	{
		const float x0=lo[0], y0=lo[1], z0=lo[2], x1=hi[0], y1=hi[1], z1=hi[2];
		const float pxL[3]={x0,y0,z0},pxL2[3]={x0,y0,z1},pxL3[3]={x0,y1,z1},pxL4[3]={x0,y1,z0};
		quad(pxL, pxL2, pxL3, pxL4, -1,0,0, r,g,bl);                                        // -X
		const float a[3]={x1,y0,z1},b[3]={x1,y0,z0},c[3]={x1,y1,z0},d[3]={x1,y1,z1};
		quad(a,b,c,d, 1,0,0, r,g,bl);                                                       // +X
		const float e[3]={x0,y0,z0},f[3]={x1,y0,z0},gg[3]={x1,y0,z1},h[3]={x0,y0,z1};
		quad(e,f,gg,h, 0,-1,0, r,g,bl);                                                     // -Y
		const float i[3]={x0,y1,z1},j[3]={x1,y1,z1},k[3]={x1,y1,z0},l[3]={x0,y1,z0};
		quad(i,j,k,l, 0,1,0, r,g,bl);                                                       // +Y
		const float m[3]={x1,y0,z0},n[3]={x0,y0,z0},o[3]={x0,y1,z0},p[3]={x1,y1,z0};
		quad(m,n,o,p, 0,0,-1, r,g,bl);                                                      // -Z
		const float q[3]={x0,y0,z1},s[3]={x1,y0,z1},t[3]={x1,y1,z1},u[3]={x0,y1,z1};
		quad(q,s,t,u, 0,0,1, r,g,bl);                                                       // +Z
	}
};

// Walls of the classic Cornell Box (interior of [-1,1]^3, open front at z=-1) + the area
// light: 6 quads = 12 triangles, matching cs_cornellbox.slang. Normals point into the room.
static void buildWalls(RtMesh& _mesh)
{
	const float W[3] = { 0.73f, 0.73f, 0.73f };
	const float R[3] = { 0.65f, 0.05f, 0.05f };
	const float G[3] = { 0.12f, 0.45f, 0.15f };

	{ float a[3]={-1,-1,-1},b[3]={1,-1,-1},c[3]={1,-1,1},d[3]={-1,-1,1}; _mesh.quad(a,b,c,d, 0,1,0,  W[0],W[1],W[2]); } // floor
	{ float a[3]={-1,1,1},b[3]={1,1,1},c[3]={1,1,-1},d[3]={-1,1,-1};     _mesh.quad(a,b,c,d, 0,-1,0, W[0],W[1],W[2]); } // ceiling
	{ float a[3]={-1,-1,1},b[3]={1,-1,1},c[3]={1,1,1},d[3]={-1,1,1};     _mesh.quad(a,b,c,d, 0,0,-1, W[0],W[1],W[2]); } // back
	{ float a[3]={-1,-1,-1},b[3]={-1,-1,1},c[3]={-1,1,1},d[3]={-1,1,-1}; _mesh.quad(a,b,c,d, 1,0,0,  R[0],R[1],R[2]); } // left (red)
	{ float a[3]={1,-1,1},b[3]={1,-1,-1},c[3]={1,1,-1},d[3]={1,1,1};     _mesh.quad(a,b,c,d, -1,0,0, G[0],G[1],G[2]); } // right (green)

	// Area light just below the ceiling.
	{ float a[3]={-0.35f,0.998f,0.35f},b[3]={0.35f,0.998f,0.35f},c[3]={0.35f,0.998f,-0.35f},d[3]={-0.35f,0.998f,-0.35f};
	  _mesh.quad(a,b,c,d, 0,-1,0, 0,0,0, 18.0f,18.0f,18.0f); }
}

// The two boxes are authored in BLAS-local space, centred (in xz) on the origin, so their
// TLAS instance transforms can rotate them about their own axes. World placement (matching
// the analytic fallback): tall at (-0.37, 0.15), short at (0.35, -0.30).
static const float kTallLo[3]  = { -0.25f, -1.0f, -0.25f };
static const float kTallHi[3]  = {  0.25f,  0.3f,  0.25f };
static const float kTallCenter[3]  = { -0.37f, 0.0f,  0.15f };
static const float kShortLo[3] = { -0.25f, -1.0f, -0.25f };
static const float kShortHi[3] = {  0.25f, -0.4f,  0.25f };
static const float kShortCenter[3] = {  0.35f, 0.0f, -0.30f };

// --- fullscreen display quad ------------------------------------------------------------

struct PosTexCoord0Vertex
{
	float m_x;
	float m_y;
	float m_z;
	float m_u;
	float m_v;

	static void init()
	{
		ms_layout
			.begin()
			.add(bgfx::Attrib::Position,  3, bgfx::AttribType::Float)
			.add(bgfx::Attrib::TexCoord0, 2, bgfx::AttribType::Float)
			.end();
	}

	static bgfx::VertexLayout ms_layout;
};

bgfx::VertexLayout PosTexCoord0Vertex::ms_layout;

void screenSpaceQuad(bool _originBottomLeft, float _width = 1.0f, float _height = 1.0f)
{
	if (3 == bgfx::getAvailTransientVertexBuffer(3, PosTexCoord0Vertex::ms_layout) )
	{
		bgfx::TransientVertexBuffer vb;
		bgfx::allocTransientVertexBuffer(&vb, 3, PosTexCoord0Vertex::ms_layout);
		PosTexCoord0Vertex* vertex = (PosTexCoord0Vertex*)vb.data;

		const float minx = -_width;
		const float maxx =  _width;
		const float miny = 0.0f;
		const float maxy =  _height*2.0f;

		const float minu = -1.0f;
		const float maxu =  1.0f;

		const float zz = 0.0f;

		float minv = 0.0f;
		float maxv = 2.0f;

		if (_originBottomLeft)
		{
			float temp = minv;
			minv = maxv;
			maxv = temp;

			minv -= 1.0f;
			maxv -= 1.0f;
		}

		vertex[0].m_x = minx;
		vertex[0].m_y = miny;
		vertex[0].m_z = zz;
		vertex[0].m_u = minu;
		vertex[0].m_v = minv;

		vertex[1].m_x = maxx;
		vertex[1].m_y = miny;
		vertex[1].m_z = zz;
		vertex[1].m_u = maxu;
		vertex[1].m_v = minv;

		vertex[2].m_x = maxx;
		vertex[2].m_y = maxy;
		vertex[2].m_z = zz;
		vertex[2].m_u = maxu;
		vertex[2].m_v = maxv;

		bgfx::setVertexBuffer(0, &vb);
	}
}

class ExampleCornellBox : public entry::AppI
{
public:
	ExampleCornellBox(const char* _name, const char* _description, const char* _url)
		: entry::AppI(_name, _description, _url)
		, m_width(0)
		, m_height(0)
		, m_debug(0)
		, m_reset(0)
		, m_texWidth(0)
		, m_texHeight(0)
	{
	}

	void init(int32_t _argc, const char* const* _argv, uint32_t _width, uint32_t _height) override
	{
		Args args(_argc, _argv);

		m_width  = _width;
		m_height = _height;
		m_debug  = BGFX_DEBUG_TEXT;
		m_reset  = BGFX_RESET_VSYNC;

		bgfx::Init init;
		init.type     = args.m_type;
		init.vendorId = args.m_pciId;
		init.platformData.nwh  = entry::getNativeWindowHandle(entry::kDefaultWindowHandle);
		init.platformData.ndt  = entry::getNativeDisplayHandle();
		init.platformData.type = entry::getNativeWindowHandleType();
		init.resolution.width  = m_width;
		init.resolution.height = m_height;
		init.resolution.reset  = m_reset;
		bgfx::init(init);

		bgfx::setDebug(m_debug);

		bgfx::setViewClear(kViewDisplay, BGFX_CLEAR_COLOR|BGFX_CLEAR_DEPTH, 0x101010ff, 1.0f, 0);

		m_computeSupported = 0 != (bgfx::getCaps()->supported & BGFX_CAPS_COMPUTE);
		m_rtSupported      = m_computeSupported && 0 != (bgfx::getCaps()->supported & BGFX_CAPS_RAY_TRACING);

		PosTexCoord0Vertex::init();

		if (m_computeSupported)
		{
			m_csProgram      = bgfx::createProgram(loadShader("cs_cornellbox"), true);
			m_displayProgram = loadProgram("vs_cornellbox", "fs_cornellbox");
			s_texColor       = bgfx::createUniform("s_texColor", bgfx::UniformType::Sampler);
			u_params         = bgfx::createUniform("u_params", bgfx::UniformType::Vec4);
			m_outputTex.idx  = bgfx::kInvalidHandle;
			m_accumTex.idx   = bgfx::kInvalidHandle;
			createOutputTextures(m_width, m_height);
		}

		// Hardware ray-query path: three BLASes (walls+light, tall box, short box) with the
		// boxes in local space so their TLAS instances can rotate; per-triangle materials in
		// one buffer ordered [walls | tall | short] (12 triangles each). Falls back to the
		// analytic path tracer above when BGFX_CAPS_RAY_TRACING is absent.
		if (m_rtSupported)
		{
			RtMesh walls, tall, shrt;
			buildWalls(walls);
			tall.box(kTallLo,  kTallHi,  0.73f, 0.73f, 0.73f);
			shrt.box(kShortLo, kShortHi, 0.73f, 0.73f, 0.73f);

			bgfx::VertexLayout posLayout;
			posLayout.begin().add(bgfx::Attrib::Position, 3, bgfx::AttribType::Float).end();

			bgfx::VertexLayout matLayout;
			matLayout.begin()
				.add(bgfx::Attrib::TexCoord0, 4, bgfx::AttribType::Float)
				.add(bgfx::Attrib::TexCoord1, 4, bgfx::AttribType::Float)
				.add(bgfx::Attrib::TexCoord2, 4, bgfx::AttribType::Float)
				.end();

			const RtMesh* meshes[kNumBlas] = { &walls, &tall, &shrt };
			std::vector<RtMaterial> materials;
			for (uint32_t ii = 0; ii < kNumBlas; ++ii)
			{
				const RtMesh& mesh = *meshes[ii];
				m_vbh[ii] = bgfx::createVertexBuffer(
					  bgfx::copy(mesh.m_positions.data(), uint32_t(mesh.m_positions.size()*sizeof(float) ) )
					, posLayout
					);
				m_ibh[ii] = bgfx::createIndexBuffer(
					  bgfx::copy(mesh.m_indices.data(), uint32_t(mesh.m_indices.size()*sizeof(uint16_t) ) )
					);
				m_blas[ii] = bgfx::createBlas(m_vbh[ii], m_ibh[ii]);
				materials.insert(materials.end(), mesh.m_materials.begin(), mesh.m_materials.end() );
			}

			m_materialBuf = bgfx::createVertexBuffer(
				  bgfx::copy(materials.data(), uint32_t(materials.size()*sizeof(RtMaterial) ) )
				, matLayout
				, BGFX_BUFFER_COMPUTE_READ
				);

			m_tlas = bgfx::createTlas(m_blas, kNumBlas);
			updateTlasTransforms(); // place the boxes (angle 0)

			m_rqProgram = bgfx::createProgram(loadShader("cs_cornellbox_rq"), true);
		}

		m_timeOffset = bx::getHPCounter();
		imguiCreate();
	}

	int shutdown() override
	{
		imguiDestroy();

		if (m_rtSupported)
		{
			if (bgfx::isValid(m_tlas) )        bgfx::destroy(m_tlas);
			for (uint32_t ii = 0; ii < kNumBlas; ++ii)
			{
				if (bgfx::isValid(m_blas[ii]) ) bgfx::destroy(m_blas[ii]);
				if (bgfx::isValid(m_ibh[ii]) )  bgfx::destroy(m_ibh[ii]);
				if (bgfx::isValid(m_vbh[ii]) )  bgfx::destroy(m_vbh[ii]);
			}
			if (bgfx::isValid(m_materialBuf) ) bgfx::destroy(m_materialBuf);
			if (bgfx::isValid(m_rqProgram) )   bgfx::destroy(m_rqProgram);
		}

		if (m_computeSupported)
		{
			if (bgfx::isValid(m_accumTex) )       bgfx::destroy(m_accumTex);
			if (bgfx::isValid(m_outputTex) )      bgfx::destroy(m_outputTex);
			if (bgfx::isValid(u_params) )         bgfx::destroy(u_params);
			if (bgfx::isValid(s_texColor) )       bgfx::destroy(s_texColor);
			if (bgfx::isValid(m_displayProgram) ) bgfx::destroy(m_displayProgram);
			if (bgfx::isValid(m_csProgram) )      bgfx::destroy(m_csProgram);
		}

		bgfx::shutdown();

		return 0;
	}

	void createOutputTextures(uint32_t _width, uint32_t _height)
	{
		if (bgfx::isValid(m_outputTex) )
		{
			bgfx::destroy(m_outputTex);
		}

		if (bgfx::isValid(m_accumTex) )
		{
			bgfx::destroy(m_accumTex);
		}

		m_texWidth  = _width;
		m_texHeight = _height;
		m_outputTex = bgfx::createTexture2D(
			  uint16_t(_width)
			, uint16_t(_height)
			, false
			, 1
			, bgfx::TextureFormat::RGBA8
			, BGFX_TEXTURE_COMPUTE_WRITE
			| BGFX_SAMPLER_MIN_POINT
			| BGFX_SAMPLER_MAG_POINT
			| BGFX_SAMPLER_U_CLAMP
			| BGFX_SAMPLER_V_CLAMP
			);
		m_accumTex = bgfx::createTexture2D(
			  uint16_t(_width)
			, uint16_t(_height)
			, false
			, 1
			, bgfx::TextureFormat::RGBA32F
			, BGFX_TEXTURE_COMPUTE_WRITE
			);

		m_resetAccum = true;
	}

	// Instance transforms in createTlas order: walls (identity), tall box (+angle), short
	// box (-angle). bx matrices; each box rotates about its own axis, then translates to
	// its world centre.
	void updateTlasTransforms()
	{
		float xf[kNumBlas*16];
		bx::mtxIdentity(&xf[0]);

		float rot[16], trn[16];
		bx::mtxRotateY(rot, m_angle);
		bx::mtxTranslate(trn, kTallCenter[0], kTallCenter[1], kTallCenter[2]);
		bx::mtxMul(&xf[16], rot, trn);

		bx::mtxRotateY(rot, -m_angle);
		bx::mtxTranslate(trn, kShortCenter[0], kShortCenter[1], kShortCenter[2]);
		bx::mtxMul(&xf[32], rot, trn);

		bgfx::updateTlas(m_tlas, bgfx::copy(xf, sizeof(xf) ) );
	}

	bool update() override
	{
		if (entry::processEvents(m_width, m_height, m_debug, m_reset, &m_mouseState) )
		{
			return false;
		}

		// Spacebar toggles the rotation mode (edge-triggered).
		const bool spaceDown = inputGetKeyState(entry::Key::Space);
		if (spaceDown && !m_spaceWasDown)
		{
			m_rotate = !m_rotate;
			m_resetAccum = true;
		}
		m_spaceWasDown = spaceDown;

		imguiBeginFrame(m_mouseState.m_mx, m_mouseState.m_my
			, (m_mouseState.m_buttons[entry::MouseButton::Left]   ? IMGUI_MBUT_LEFT   : 0)
			| (m_mouseState.m_buttons[entry::MouseButton::Right]  ? IMGUI_MBUT_RIGHT  : 0)
			| (m_mouseState.m_buttons[entry::MouseButton::Middle] ? IMGUI_MBUT_MIDDLE : 0)
			, m_mouseState.m_mz, uint16_t(m_width), uint16_t(m_height)
			);

		showExampleDialog(this);

		ImGui::SetNextWindowPos(ImVec2(m_width - 280.0f, 40.0f), ImGuiCond_FirstUseEver);
		ImGui::Begin("Cornell Box (Slang)");
		ImGui::TextWrapped(m_rtSupported
			? "Path: hardware ray query (BLAS/TLAS, BGFX_CAPS_RAY_TRACING)."
			: "Path: compute fallback (analytic path tracer; no hardware RT)."
			);
		if (ImGui::Checkbox("Rotate boxes (Space)", &m_rotate) )
		{
			m_resetAccum = true;
		}
		ImGui::End();

		imguiEndFrame();

		if (m_computeSupported)
		{
			if (m_texWidth != m_width || m_texHeight != m_height)
			{
				createOutputTextures(m_width, m_height);
			}

			const bgfx::Caps* caps = bgfx::getCaps();

			// Advance the boxes; while they move, every frame is a fresh 1-sample/pixel
			// image (the accumulation restarts), converging again once they stop.
			const int64_t now = bx::getHPCounter();
			const float dt = float(double(now - m_lastFrameTime) / double(bx::getHPFrequency() ) );
			m_lastFrameTime = now;

			if (m_rotate)
			{
				m_angle += dt * 0.7f;
				m_resetAccum = true;

				if (m_rtSupported)
				{
					updateTlasTransforms();
				}
			}

			const float params[4] = { float(m_frameIdx), m_resetAccum ? 1.0f : 0.0f, m_angle, 0.0f };
			bgfx::setUniform(u_params, params);

			// Path trace into the accumulation image; the shader writes the tonemapped
			// running average to the display image.
			if (m_rtSupported)
			{
				bgfx::setAccelerationStructure(0, m_tlas);                                          // scene     (stage 0)
				bgfx::setImage(1, m_accumTex,  0, bgfx::Access::ReadWrite, bgfx::TextureFormat::RGBA32F); // s_accum  (stage 1)
				bgfx::setImage(2, m_outputTex, 0, bgfx::Access::Write,     bgfx::TextureFormat::RGBA8);   // s_target (stage 2)
				bgfx::setBuffer(3, m_materialBuf, bgfx::Access::Read);                              // materials (stage 3)
				bgfx::dispatch(kViewCompute, m_rqProgram, (m_width + 7)/8, (m_height + 7)/8, 1);
			}
			else
			{
				bgfx::setImage(0, m_accumTex,  0, bgfx::Access::ReadWrite, bgfx::TextureFormat::RGBA32F); // s_accum  (stage 0)
				bgfx::setImage(1, m_outputTex, 0, bgfx::Access::Write,     bgfx::TextureFormat::RGBA8);   // s_target (stage 1)
				bgfx::dispatch(kViewCompute, m_csProgram, (m_width + 7)/8, (m_height + 7)/8, 1);
			}

			m_resetAccum = false;
			++m_frameIdx;

			// Blit the image to the backbuffer with a fullscreen quad.
			float ortho[16];
			bx::mtxOrtho(ortho, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 100.0f, 0.0f, caps->homogeneousDepth);
			bgfx::setViewRect(kViewDisplay, 0, 0, uint16_t(m_width), uint16_t(m_height) );
			bgfx::setViewTransform(kViewDisplay, NULL, ortho);
			bgfx::setTexture(0, s_texColor, m_outputTex);
			bgfx::setState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_A);
			screenSpaceQuad(caps->originBottomLeft);
			bgfx::submit(kViewDisplay, m_displayProgram);
		}
		else
		{
			bgfx::touch(kViewDisplay);
			bgfx::dbgTextClear();
			bgfx::dbgTextPrintf(0, 1, 0x4f, "Compute is not supported by this GPU.");
		}

		bgfx::frame();

		return true;
	}

	static constexpr bgfx::ViewId kViewCompute = 0;
	static constexpr bgfx::ViewId kViewDisplay = 1;
	static constexpr uint32_t     kNumBlas     = 3; // walls+light, tall box, short box

	entry::MouseState m_mouseState;

	uint32_t m_width;
	uint32_t m_height;
	uint32_t m_debug;
	uint32_t m_reset;

	uint32_t m_texWidth;
	uint32_t m_texHeight;

	bool m_computeSupported = false;
	bool m_rtSupported      = false;

	bool     m_rotate       = false;
	bool     m_spaceWasDown = false;
	bool     m_resetAccum   = true;
	float    m_angle        = 0.0f;
	uint32_t m_frameIdx     = 0;
	int64_t  m_timeOffset   = 0;
	int64_t  m_lastFrameTime = 0;

	bgfx::ProgramHandle m_csProgram      = BGFX_INVALID_HANDLE;
	bgfx::ProgramHandle m_rqProgram      = BGFX_INVALID_HANDLE;
	bgfx::ProgramHandle m_displayProgram = BGFX_INVALID_HANDLE;
	bgfx::TextureHandle m_outputTex      = BGFX_INVALID_HANDLE;
	bgfx::TextureHandle m_accumTex       = BGFX_INVALID_HANDLE;
	bgfx::UniformHandle s_texColor       = BGFX_INVALID_HANDLE;
	bgfx::UniformHandle u_params         = BGFX_INVALID_HANDLE;

	// Ray-query path resources.
	bgfx::VertexBufferHandle          m_vbh[kNumBlas]  = { BGFX_INVALID_HANDLE, BGFX_INVALID_HANDLE, BGFX_INVALID_HANDLE };
	bgfx::IndexBufferHandle           m_ibh[kNumBlas]  = { BGFX_INVALID_HANDLE, BGFX_INVALID_HANDLE, BGFX_INVALID_HANDLE };
	bgfx::VertexBufferHandle          m_materialBuf    = BGFX_INVALID_HANDLE;
	bgfx::AccelerationStructureHandle m_blas[kNumBlas] = { BGFX_INVALID_HANDLE, BGFX_INVALID_HANDLE, BGFX_INVALID_HANDLE };
	bgfx::AccelerationStructureHandle m_tlas           = BGFX_INVALID_HANDLE;
};

} // namespace

ENTRY_IMPLEMENT_MAIN(
	  ExampleCornellBox
	, "52-cornellbox"
	, "Cornell Box path traced in a Slang shader (ray query + compute fallback)."
	, "https://bkaradzic.github.io/bgfx/examples.html#cornellbox"
	);
