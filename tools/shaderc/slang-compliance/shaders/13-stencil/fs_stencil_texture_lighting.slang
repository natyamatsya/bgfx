// 1-to-1 Slang port of examples/13-stencil fs_stencil_texture_lighting.sc.
// blinn/lit/calcLight are defined inline in the .sc body, so they stay inline here.
// Predefined u_view is auto-declared; use it directly.
import bgfx_shader;

static const int MAX_NUM_LIGHTS = 5;

vec4 u_params;
vec4 u_ambient;
vec4 u_diffuse;
vec4 u_color;
vec4 u_specular_shininess;
vec4 u_lightPosRadius[MAX_NUM_LIGHTS];
vec4 u_lightRgbInnerR[MAX_NUM_LIGHTS];

// SAMPLER2D(s_texColor, 0)
Texture2D    s_texColor        : register(t0);
SamplerState s_texColorSampler : register(s0);

// u_ambientPass  = u_params.x
// u_lightingPass = u_params.y
// u_lightCount   = u_params.z
// u_lightIndex   = u_params.w
// u_specular     = u_specular_shininess.xyz
// u_shininess    = u_specular_shininess.w

vec2 blinn(vec3 _lightDir, vec3 _normal, vec3 _viewDir)
{
	float ndotl = dot(_normal, _lightDir);
	vec3 reflected = 2.0*ndotl*_normal - _lightDir; // reflect(_lightDir, _normal);
	float rdotv = dot(reflected, _viewDir);
	return vec2(ndotl, rdotv);
}

vec4 lit(float _ndotl, float _rdotv, float _m)
{
	float diff = max(0.0, _ndotl);
	float spec = step(0.0, _ndotl) * pow(max(0.0, _rdotv), _m);
	return vec4(1.0, diff, spec, 1.0);
}

vec3 calcLight(int _idx, vec3 _view, vec3 _normal, vec3 _viewDir)
{
	vec3 lightPos = mul(u_view, vec4(u_lightPosRadius[_idx].xyz, 1.0)).xyz;
	vec3 toLight = lightPos - _view;
	vec3 lightDir = normalize(toLight);

	vec2 bln = blinn(lightDir, _normal, _viewDir);
	vec4 lc = lit(bln.x, bln.y, u_specular_shininess.w);

	float dist = max(length(toLight), u_lightPosRadius[_idx].w);
	float attn = 250.0 * pow(dist, -2.0);
	vec3 rgb = (lc.y * u_diffuse.xyz + lc.z * u_specular_shininess.xyz) * u_lightRgbInnerR[_idx].rgb * attn;

	return rgb;
}

struct V2F
{
	float4 pos         : SV_Position;
	vec3   v_normal    : NORMAL;
	vec3   v_view      : TEXCOORD1;
	vec2   v_texcoord0 : TEXCOORD0;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	vec3 normal = normalize(input.v_normal);
	vec3 viewDir = -normalize(input.v_view);

	vec3 ambientColor = u_ambient.xyz * u_params.x;

	vec3 lightColor = vec3_splat(0.0);
	for(int ii = 0; ii < MAX_NUM_LIGHTS; ++ii)
	{
		float condition = 0.0;
		if (u_params.z > 1.0) // Stencil Reflection Scene.
		{
			condition = 1.0 - step(u_params.z, float(ii)); // True for every light up to u_lightCount.
		}
		else // Projection Shadows Scene.
		{
			condition = float(float(ii) == u_params.w); // True only for current light.
		}

		lightColor += calcLight(ii, input.v_view, normal, viewDir) * condition;
	}
	lightColor *= u_params.y;

	vec3 color = toLinear(texture2D(s_texColor, s_texColorSampler, input.v_texcoord0)).xyz;

	vec3 ambient = toGamma(ambientColor * color);
	vec3 diffuse = toGamma(lightColor * color);

	float4 gl_FragColor;
	gl_FragColor.xyz = clamp(ambient + diffuse, 0.0, 1.0);
	gl_FragColor.w = u_color.w;
	return gl_FragColor;
}
