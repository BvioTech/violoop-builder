# Builder for violoop-pro

This is builder for violoop cross compile.

## Files

All files in `sysroot` are copied from target system.

- `toolchain`, download from `https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads`

## CMake

```bash
cmake -DCMAKE_TOOLCHAIN_FILE=/workspace/toolchain.cmake ..
```
