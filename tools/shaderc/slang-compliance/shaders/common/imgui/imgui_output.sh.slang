// Slang port of examples/common/imgui/imgui_output.sh -- the ImGui output transform that
// 55-hdr10 drives: SDR passthrough, sRGB-decoded linear scaled to the SDR white level, or
// BT.2020 + PQ for an HDR10 back buffer. `import imgui_output;`.
//
// Copyright 2011-2026 Branimir Karadzic. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
//
// The stock header declares u_imguiOutput and reads it through #define accessors. Neither
// survives an `import` (see 53-sky2/atmosphere.sh.slang), so this is a pure function and each
// importer declares the uniform itself:
//
//   u_imguiOutputMode  u_imguiOutput.x    u_imguiOutputWhite u_imguiOutput.y
import bgfx_shader;
import bgfx_shader_glsl_compat;

public vec3 imguiOutput(vec3 _rgb, vec4 _output)
{
	if (_output.x < 0.5)
	{
		return _rgb;
	}

	vec3 lo  = _rgb / 12.92;
	vec3 hi  = pow( (_rgb + 0.055) / 1.055, vec3_splat(2.4) );
	vec3 rgb = mix(hi, lo, vec3(lessThanEqual(_rgb, vec3_splat(0.04045) ) ) ) * _output.y;

	if (_output.x < 1.5)
	{
		return rgb;
	}

	vec3 bt2020 = vec3(
		  dot(vec3(0.6274, 0.3293, 0.0433), rgb)
		, dot(vec3(0.0691, 0.9195, 0.0114), rgb)
		, dot(vec3(0.0164, 0.0880, 0.8956), rgb)
		);

	const float m1 = 2610.0/16384.0;
	const float m2 = 2523.0/4096.0*128.0;
	const float c1 = 3424.0/4096.0;
	const float c2 = 2413.0/4096.0*32.0;
	const float c3 = 2392.0/4096.0*32.0;

	vec3 yy = pow(clamp(bt2020, 0.0, 1.0), vec3_splat(m1) );
	return pow( (c1 + c2*yy) / (1.0 + c3*yy), vec3_splat(m2) );
}
