// 1-to-1 Slang port of examples/33-pom fs_pom.sc (per-stage). parallax_uv is
// defined inline in the .sc body, so it stays inline here. texture2DBc5 comes
// from shaderlib; mix from bgfx_shader_glsl_compat.
import bgfx_shader;
import bgfx_shader_glsl_compat;
import shaderlib;

Texture2D    s_texColor         : register(t0);
SamplerState s_texColorSampler  : register(s0);
Texture2D    s_texNormal        : register(t1);
SamplerState s_texNormalSampler : register(s1);
Texture2D    s_texDepth         : register(t2);
SamplerState s_texDepthSampler  : register(s2);

float4 u_pomParam;

#define u_shading_type         u_pomParam.x
#define u_show_diffuse_texture u_pomParam.y
#define u_parallax_scale       u_pomParam.z
#define u_num_steps            u_pomParam.w

struct V2F
{
	vec2 v_texcoord0    : TEXCOORD0;
	vec3 v_ts_light_pos : TEXCOORD1;
	vec3 v_ts_view_pos  : TEXCOORD2;
	vec3 v_ts_frag_pos  : TEXCOORD3;
};

vec2 parallax_uv(vec2 uv, vec3 view_dir)
{
	float depth_scale = float(u_parallax_scale) / 1000.0;
	if (u_shading_type == 2.0)
	{
		// Parallax mapping
		float depth = texture2D(s_texDepth, s_texDepthSampler, uv).r;
		vec2 p = view_dir.xy * (depth * depth_scale) / view_dir.z;
		return uv - p;
	}
	else
	{
		float layer_depth = 1.0 / float(u_num_steps);
		float cur_layer_depth = 0.0;
		vec2 delta_uv = view_dir.xy * depth_scale / (view_dir.z * u_num_steps);
		vec2 cur_uv = uv;

		float depth_from_tex = texture2D(s_texDepth, s_texDepthSampler, cur_uv).r;

		for (int i = 0; i < 32; i++)
		{
			cur_layer_depth += layer_depth;
			cur_uv -= delta_uv;
			depth_from_tex = texture2D(s_texDepth, s_texDepthSampler, cur_uv).r;
			if (depth_from_tex < cur_layer_depth)
			{
				break;
			}
		}

		if (u_shading_type == 3.0)
		{
			// Steep parallax mapping
			return cur_uv;
		}
		else
		{
			// Parallax occlusion mapping
			vec2 prev_uv = cur_uv + delta_uv;
			float next = depth_from_tex - cur_layer_depth;
			float prev = texture2D(s_texDepth, s_texDepthSampler, prev_uv).r - cur_layer_depth + layer_depth;
			float weight = next / (next - prev);
			return mix(cur_uv, prev_uv, weight);
		}
	}
}

[shader("fragment")]
float4 fragmentMain(V2F input) : SV_Target
{
	vec3 light_dir = normalize(input.v_ts_light_pos - input.v_ts_frag_pos);
	vec3 view_dir  = normalize(input.v_ts_view_pos  - input.v_ts_frag_pos);

	// Only perturb the texture coordinates if a parallax technique is selected
	vec2 uv = (u_shading_type < 2.0) ? input.v_texcoord0 : parallax_uv(input.v_texcoord0, view_dir);

	vec3 albedo;
	if (u_show_diffuse_texture == 0.0)
	{
		albedo = vec3(1.0, 1.0, 1.0);
	}
	else
	{
		albedo = texture2D(s_texColor, s_texColorSampler, uv).rgb;
	}

	vec3 ambient = 0.3 * albedo;

	vec3 normal;

	if (u_shading_type == 0.0)
	{
		normal = vec3(0.0, 0.0, 1.0);
	}
	else
	{
		normal.xy = texture2DBc5(s_texNormal, s_texNormalSampler, uv) * 2.0 - 1.0;
		normal.z  = sqrt(1.0 - dot(normal.xy, normal.xy) );
	}

	float diffuse = max(dot(light_dir, normal), 0.0);
	return vec4(diffuse * albedo + ambient, 1.0);
}
