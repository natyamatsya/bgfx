// 1-to-1 Slang port of examples/31-rsm vs_rsm_lbuffer.sc.
// Light-buffer pass: reconstructs each light's world position from the shadow map,
// scales the proxy sphere by the radius stored in the RSM, and passes the light
// center/scale + color to the fragment shader. Note the samplers are bound to the
// VERTEX shader here (texture slots start at 2). u_viewProj is auto-provided.
import bgfx_shader;
import shaderlib; // toClipSpaceDepth, clipToWorld

uniform vec4 u_sphereInfo;
uniform mat4 u_invMvpShadow;

// Note texture binding starts at slot 2.  Problem is that vert textures and frag textures are different.
Texture2D    s_shadowMap        : register(t2); // Used to reconstruct 3d position for lights
SamplerState s_shadowMapSampler : register(s2);
Texture2D    s_rsm              : register(t3); // Reflective shadow map, used to scale/color light
SamplerState s_rsmSampler       : register(s3);

struct VSInput
{
	vec3 a_position : POSITION;
};

struct V2F
{
	vec4 pos                : SV_Position;
	vec4 v_lightCenterScale : TEXCOORD2;
	vec4 v_color0           : COLOR0;
};

[shader("vertex")]
V2F vertexMain(VSInput input)
{
	V2F output;

	// Calculate vertex position
	vec3 objectSpacePos = input.a_position;
	vec2 texCoord       = u_sphereInfo.xy;

	// Get world position using the shadow map
	float deviceDepth = texture2DLod(s_shadowMap, s_shadowMapSampler, texCoord, 0).x;
	float depth       = toClipSpaceDepth(deviceDepth);
	vec3 clip = vec3(texCoord * 2.0 - 1.0, depth);
	clip.y = -clip.y; // !BGFX_SHADER_LANGUAGE_GLSL
	vec3 wPos = clipToWorld(u_invMvpShadow, clip);
	wPos.y -= 0.001;  // Would be much better to perturb in normal direction, but I didn't do that.

	// Scale and color are already in the rsm
	vec4 rsm = texture2DLod(s_rsm, s_rsmSampler, texCoord, 0).xyzw;
	float radScale = u_sphereInfo.z;
	float rad = rsm.w * radScale;

	output.pos = mul(u_viewProj, vec4(wPos+objectSpacePos*rad, 1.0) );

	output.v_lightCenterScale.xyz = wPos.xyz;
	output.v_lightCenterScale.w = rad;
	output.v_color0.xyz = rsm.xyz;

	return output;
}
