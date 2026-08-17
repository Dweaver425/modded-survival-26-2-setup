# RAM Guide

Minecraft's `-Xmx` value is the maximum Java heap, not the total memory used by the game. Shaders, graphics drivers, Distant Horizons, Voxy, the operating system, and background applications also use memory outside this limit.

## Recommended Values

| Client pack | Recommended | Normal range | Notes |
| --- | ---: | ---: | --- |
| Windows Max - Voxy | `-Xmx12G` | 10-12 GB | Intended for a high-end PC with at least 32 GB system RAM |
| Windows - Distant Horizons | `-Xmx8G` | 6-10 GB | DH also uses memory outside the Java heap |
| Windows - No LOD | `-Xmx6G` | 5-8 GB | Best balance for a typical friend PC |
| Mac - Distant Horizons | `-Xmx6G` | 5-8 GB | Leave room for macOS and shared GPU memory |
| Mac - No LOD | `-Xmx5G` | 4-6 GB | Recommended Mac starting point |
| Universal - Extreme Low End | `-Xmx4G` | 3-4 GB | Use 3 GB on a computer with only 8 GB total RAM |

## Choose By Total System Memory

| Total system memory | Suggested maximum for Minecraft |
| ---: | ---: |
| 8 GB | 3-4 GB |
| 16 GB | 6-8 GB |
| 24 GB | 8-10 GB |
| 32 GB or more | 10-12 GB for the Max Voxy pack |

On Apple Silicon, system RAM is unified memory shared by macOS, Minecraft, and the GPU. Avoid assigning most of it to Java.

## Change The Value

In Minecraft Launcher:

1. Open **Minecraft: Java Edition > Installations**.
2. Find the modded installation and select **Edit**.
3. Open **More Options**.
4. Find the existing `-Xmx` argument.
5. Replace that one value and save.

Example for 8 GB:

```text
-Xmx8G
```

Do not add multiple `-Xmx` arguments. Keep the launcher's other JVM settings unchanged.

## When To Adjust It

- Increase by 1-2 GB if the crash report explicitly says `OutOfMemoryError` and the computer has enough unused system memory.
- Reduce the value if the entire computer swaps, freezes, or closes background applications.
- Lower render distance, shader quality, or LOD distance before assigning excessive RAM.
- More RAM will not fix incompatible mods, GPU-driver crashes, or a server connection timeout.

