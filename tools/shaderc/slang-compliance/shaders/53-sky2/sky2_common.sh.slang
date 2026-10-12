// Slang port of examples/53-sky2/sky2_common.sh.
//
// Copyright 2026 Mateusz Kozdrowicki. All rights reserved.
// License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
import bgfx_shader;

public static const float SKY2_EXPOSURE = 1.6;

// ACES filmic Narkowicz 2015 fit.
public vec3 sky2_tonemap(vec3 color)
{
	color *= SKY2_EXPOSURE;
	vec3 num = color * (2.51 * color + 0.03);
	vec3 den = color * (2.43 * color + 0.59) + 0.14;
	return saturate(num / den);
}
