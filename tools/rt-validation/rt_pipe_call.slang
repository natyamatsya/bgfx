// Callable shader: contributes a fixed amount through the callable data block.
struct CallableData
{
	float add;
};

[shader("callable")]
void callableMain(inout CallableData d)
{
	d.add = 0.5;
}
