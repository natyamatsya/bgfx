--
-- Copyright 2011-2026 Branimir Karadzic. All rights reserved.
-- License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
--

-- Headless ray-tracing runtime validation tools (see tools/rt-validation/README.md and
-- RT_ROADMAP.md / RT_WINDOWS_ROADMAP.md). Each is a standalone bgfx console app (no entry
-- framework -- a bare `int main()` that drives the acceleration-structure runtime end to
-- end), so it links bgfx + bimg + bx. bgfx's linkoptions do not propagate to consumers, so
-- the platform frameworks/libs are declared here, matching what exampleProject() links.
-- Cross-platform (SPIR-V/Metal, and DXIL on Windows once M2 lands); the raw metal-cpp
-- spikes (metal_rt_pipeline_*.cpp) are macOS-only and stay ad-hoc.

local function rtValidationTool(_name)
	project (_name)
		uuid (os.uuid("rt-validation-" .. _name) )
		kind "ConsoleApp"

		includedirs {
			path.join(BGFX_DIR, "include"),
			path.join(BIMG_DIR, "include"),
			path.join(BGFX_DIR, "3rdparty"),
		}

		files {
			path.join(BGFX_DIR, "tools/rt-validation/" .. _name .. ".cpp"),
		}

		links {
			"bgfx",
			"bimg",
		}

		using_bx()

		configuration { "linux-* or freebsd" }
			links {
				"X11",
				"GL",
				"pthread",
			}

		configuration { "osx*" }
			linkoptions {
				"-framework Cocoa",
				"-framework IOKit",
				"-framework OpenGL",
				"-framework QuartzCore",
				"-weak_framework Metal",
				"-weak_framework VideoToolbox",
				"-weak_framework CoreMedia",
				"-weak_framework CoreVideo",
			}

		configuration { "vs20*" }
			links {
				"gdi32",
				"psapi",
			}

		configuration { "mingw-*" }
			targetextension ".exe"
			links {
				"comdlg32",
				"gdi32",
				"psapi",
			}

		configuration {}
end

rtValidationTool("rt_smoke")
rtValidationTool("rt_pipeline_smoke")
rtValidationTool("rt_pipeline_p0_referee")
rtValidationTool("rt_pipeline_cornellbox")
rtValidationTool("rt_bench")
