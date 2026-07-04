// 1-to-1 Slang port of examples/36-sky fs_sky.sc.
// toGamma comes from the central bgfx_shader.
import bgfx_shader;

vec4 u_parameters; // x - sun size, y - sun bloom, z - exposition, w - time
vec4 u_sunDirection;
// u_sunLuminance is declared in the .sc but unused; glslang strips it, so it is omitted here.

struct V2F
{
	vec4 pos         : SV_Position;
	vec2 v_screenPos : TEXCOORD0;
	vec3 v_skyColor  : TEXCOORD1;
	vec3 v_viewDir   : TEXCOORD2;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	float size2 = u_parameters.x * u_parameters.x;

	vec3 lightDir = normalize(u_sunDirection.xyz);
	float dist = 2.0 * (1.0 - dot(normalize(input.v_viewDir), lightDir));
	float sun  = exp(-dist / u_parameters.y / size2) + step(dist, size2);
	float sun2 = min(sun * sun, 1.0);
	vec3 color = input.v_skyColor + sun2;
	color = toGamma(color);

	return vec4(color, 1.0);
}
