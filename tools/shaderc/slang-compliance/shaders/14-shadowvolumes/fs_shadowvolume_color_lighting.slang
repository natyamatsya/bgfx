// 1-to-1 Slang port of examples/14-shadowvolumes fs_shadowvolume_color_lighting.sc.
// blinn/lit/calcLight are defined inline in the .sc body, so they stay inline here.
// Predefined u_view / u_viewTexel are auto-declared; use them directly.
import bgfx_shader;
import bgfx_shader_glsl_compat;

vec4 u_params;
vec4 u_svparams;
vec4 u_ambient;
vec4 u_diffuse;
vec4 u_color;
vec4 u_specular_shininess;
vec4 u_fog;
vec4 u_lightPosRadius;
vec4 u_lightRgbInnerR;

// SAMPLER2D(s_texStencil, 1)
Texture2D    s_texStencil        : register(t1);
SamplerState s_texStencilSampler : register(s1);

// u_ambientPass   = u_params.x
// u_lightingPass  = u_params.y
// u_texelHalf     = u_params.z
// u_specular      = u_specular_shininess.xyz
// u_shininess     = u_specular_shininess.w
// u_fogColor      = u_fog.xyz
// u_fogDensity    = u_fog.w
// u_useStencilTex = u_svparams.x

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

vec3 calcLight(vec3 _view, vec3 _normal, vec3 _viewDir)
{
	vec3 lightPos = mul(u_view, vec4(u_lightPosRadius.xyz, 1.0)).xyz;
	vec3 toLight = lightPos - _view;
	vec3 lightDir = normalize(toLight);

	vec2 bln = blinn(lightDir, _normal, _viewDir);
	vec4 lc = lit(bln.x, bln.y, u_specular_shininess.w);

	float dist = max(length(toLight), u_lightPosRadius.w);
	float attn = 50.0 * pow(dist, -2.0);
	vec3 rgb = (lc.y * u_diffuse.xyz + lc.z * u_specular_shininess.xyz) * u_lightRgbInnerR.rgb * attn;

	return rgb;
}

struct V2F
{
	vec4 gl_FragCoord : SV_Position;
	vec3 v_normal     : NORMAL;
	vec3 v_view       : TEXCOORD2;
};

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	vec3 ambientColor = u_ambient.xyz * u_params.x;

	vec3 normal = normalize(input.v_normal);
	vec3 viewDir = -normalize(input.v_view);
	vec3 lightColor = calcLight(input.v_view, normal, viewDir) * u_params.y;

	vec2 ndc = input.gl_FragCoord.xy * u_viewTexel.xy + u_viewTexel.xy * u_params.z;
	vec4 texcolor = texture2D(s_texStencil, s_texStencilSampler, ndc);
	float s = (texcolor.x - texcolor.y) + 2.0 * (texcolor.z - texcolor.w);
	s *= u_svparams.x;

	const float LOG2 = 1.442695;
	float z = length(input.v_view);
	float fogFactor = 1.0/exp2(u_fog.w*u_fog.w*z*z*LOG2);
	fogFactor = clamp(fogFactor, 0.0, 1.0);

	vec3 color = u_color.xyz;

	vec3 ambient = toGamma(ambientColor * color);
	vec3 diffuse = toGamma(lightColor * color);
	vec3 final   = mix(ambient, ambient + diffuse, float((abs(s) < 0.0001)));

	float4 gl_FragColor;
	gl_FragColor.xyz = mix(u_fog.xyz, final, fogFactor);
	gl_FragColor.w   = 1.0;
	return gl_FragColor;
}
