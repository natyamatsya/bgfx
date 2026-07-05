/*
 * Copyright 2011-2026 Branimir Karadzic. All rights reserved.
 * License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
 */

// Cornell Box ray traced in a Slang shader.
//
// Compute fallback path: a compute shader ray-traces the scene into a texture, which a
// fullscreen quad blits to the screen. Runs wherever compute is supported, no hardware RT.
// The hardware ray-query path (gated on BGFX_CAPS_RAY_TRACING) is a follow-up that needs
// the bgfx acceleration-structure runtime; the compute path here is the fallback for it.

#include "common.h"
#include "bgfx_utils.h"
#include "imgui/imgui.h"

namespace
{

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

		PosTexCoord0Vertex::init();

		if (m_computeSupported)
		{
			m_csProgram      = bgfx::createProgram(loadShader("cs_cornellbox"), true);
			m_displayProgram = loadProgram("vs_cornellbox", "fs_cornellbox");
			s_texColor       = bgfx::createUniform("s_texColor", bgfx::UniformType::Sampler);
			m_outputTex.idx  = bgfx::kInvalidHandle;
			createOutputTexture(m_width, m_height);
		}

		imguiCreate();
	}

	int shutdown() override
	{
		imguiDestroy();

		if (m_computeSupported)
		{
			if (bgfx::isValid(m_outputTex) )      bgfx::destroy(m_outputTex);
			if (bgfx::isValid(s_texColor) )       bgfx::destroy(s_texColor);
			if (bgfx::isValid(m_displayProgram) ) bgfx::destroy(m_displayProgram);
			if (bgfx::isValid(m_csProgram) )      bgfx::destroy(m_csProgram);
		}

		bgfx::shutdown();

		return 0;
	}

	void createOutputTexture(uint32_t _width, uint32_t _height)
	{
		if (bgfx::isValid(m_outputTex) )
		{
			bgfx::destroy(m_outputTex);
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
	}

	bool update() override
	{
		if (entry::processEvents(m_width, m_height, m_debug, m_reset, &m_mouseState) )
		{
			return false;
		}

		imguiBeginFrame(m_mouseState.m_mx, m_mouseState.m_my
			, (m_mouseState.m_buttons[entry::MouseButton::Left]   ? IMGUI_MBUT_LEFT   : 0)
			| (m_mouseState.m_buttons[entry::MouseButton::Right]  ? IMGUI_MBUT_RIGHT  : 0)
			| (m_mouseState.m_buttons[entry::MouseButton::Middle] ? IMGUI_MBUT_MIDDLE : 0)
			, m_mouseState.m_mz, uint16_t(m_width), uint16_t(m_height)
			);

		showExampleDialog(this);

		ImGui::SetNextWindowPos(ImVec2(m_width - 260.0f, 40.0f), ImGuiCond_FirstUseEver);
		ImGui::Begin("Cornell Box (Slang)");
		ImGui::TextWrapped("Path: compute fallback (analytic ray tracer).");
		ImGui::TextWrapped("Hardware ray-query path is a follow-up (needs the accel-structure runtime).");
		ImGui::End();

		imguiEndFrame();

		if (m_computeSupported)
		{
			if (m_texWidth != m_width || m_texHeight != m_height)
			{
				createOutputTexture(m_width, m_height);
			}

			const bgfx::Caps* caps = bgfx::getCaps();

			// Ray trace into the output image.
			bgfx::setImage(0, m_outputTex, 0, bgfx::Access::Write, bgfx::TextureFormat::RGBA8);
			bgfx::dispatch(kViewCompute, m_csProgram, (m_width + 7)/8, (m_height + 7)/8, 1);

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

	entry::MouseState m_mouseState;

	uint32_t m_width;
	uint32_t m_height;
	uint32_t m_debug;
	uint32_t m_reset;

	uint32_t m_texWidth;
	uint32_t m_texHeight;

	bool m_computeSupported = false;

	bgfx::ProgramHandle m_csProgram      = BGFX_INVALID_HANDLE;
	bgfx::ProgramHandle m_displayProgram = BGFX_INVALID_HANDLE;
	bgfx::TextureHandle m_outputTex      = BGFX_INVALID_HANDLE;
	bgfx::UniformHandle s_texColor       = BGFX_INVALID_HANDLE;
};

} // namespace

ENTRY_IMPLEMENT_MAIN(
	  ExampleCornellBox
	, "52-cornellbox"
	, "Cornell Box ray traced in a Slang compute shader (compute fallback)."
	, "https://bkaradzic.github.io/bgfx/examples.html#cornellbox"
	);
