// Slang port of examples/41-tess/isubd.sh -- the implicit-subdivision key/xform helpers
// shared by the terrain compute + vertex shaders. `import isubd;`.
//
// Faithful 1-to-1 translation: every function is ported and made public. The subdivision
// math (keyToXform / subd) uses the bgfx_shader matrix helpers: the mat4x3 alias, the
// 3-argument mtxFromRows(vec4,vec4,vec4)->mat4x3, and mtxGetRow(mat4x3).
import bgfx_shader; // vec/mat aliases, mtxFromCols(mat3), mtxFromRows(mat4x3), mtxGetRow, mul

public uint findMSB_(uint x)
{
	uint i;
	uint mask;
	uint res = uint(-1);

	for (i = 0u; i < 32u; i++)
	{
		mask = 0x80000000u >> i;

		if ((x & mask) != 0u)
		{
			res = 31u - i;
			break;
		}
	}

	return res;
}

public uint parentKey(in uint key)
{
	return (key >> 1u);
}

public void childrenKeys(in uint key, out uint children[2])
{
	children[0] = (key << 1u) | 0u;
	children[1] = (key << 1u) | 1u;
}

public bool isRootKey(in uint key)
{
	return (key == 1u);
}

public bool isLeafKey(in uint key)
{
	return findMSB_(key) == 31u;
}

public bool isChildZeroKey(in uint key)
{
	return ((key & 1u) == 0u);
}

// barycentric interpolation
public vec3 berp(in vec3 v[3], in vec2 u)
{
	return v[0] + u.x * (v[1] - v[0]) + u.y * (v[2] - v[0]);
}

public vec4 berp(in vec4 v[3], in vec2 u)
{
	return v[0] + u.x * (v[1] - v[0]) + u.y * (v[2] - v[0]);
}

// get xform from bit value
public mat3 bitToXform(in uint bit)
{
	float b = float(bit);
	float c = 1.0f - b;

	vec3 c1 = vec3(0.0f, c   , b   );
	vec3 c2 = vec3(0.5f, b   , 0.0f);
	vec3 c3 = vec3(0.5f, 0.0f, c   );

	return mtxFromCols(c1, c2, c3);
}

// get xform from key
public mat3 keyToXform(in uint key)
{
	vec3 c1 = vec3(1.0f, 0.0f, 0.0f);
	vec3 c2 = vec3(0.0f, 1.0f, 0.0f);
	vec3 c3 = vec3(0.0f, 0.0f, 1.0f);

	mat3 xf = mtxFromCols(c1, c2, c3);

	while (key > 1u) {
		xf = mul(xf, bitToXform(key & 1u));
		key = key >> 1u;
	}

	return xf;
}

// get xform from key as well as xform from parent key
public mat3 keyToXform(in uint key, out mat3 xfp)
{
	xfp = keyToXform(parentKey(key));
	return keyToXform(key);
}

// subdivision routine (vertex position only)
public void subd(in uint key, in vec4 v_in[3], out vec4 v_out[3])
{
	mat3 xf = keyToXform(key);

	mat4x3 m = mtxFromRows(v_in[0], v_in[1], v_in[2]);

	mat4x3 v = mul(xf, m);

	v_out[0] = mtxGetRow(v, 0);
	v_out[1] = mtxGetRow(v, 1);
	v_out[2] = mtxGetRow(v, 2);
}

// subdivision routine (vertex position only)
// also computes parent position
public void subd(in uint key, in vec4 v_in[3], out vec4 v_out[3], out vec4 v_out_p[3])
{
	mat3 xfp; mat3 xf = keyToXform(key, xfp);

	mat4x3 m = mtxFromRows(v_in[0], v_in[1], v_in[2]);

	mat4x3 v  = mul(xf,  m);
	mat4x3 vp = mul(xfp, m);

	v_out[0] = mtxGetRow(v, 0);
	v_out[1] = mtxGetRow(v, 1);
	v_out[2] = mtxGetRow(v, 2);

	v_out_p[0] = mtxGetRow(vp, 0);
	v_out_p[1] = mtxGetRow(vp, 1);
	v_out_p[2] = mtxGetRow(vp, 2);
}
