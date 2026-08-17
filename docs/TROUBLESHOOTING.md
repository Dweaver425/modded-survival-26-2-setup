# Troubleshooting

## Mods Are Missing

1. Open the launcher installation's **Edit** screen.
2. Check **Game Directory**.
3. Open that exact folder in Finder or File Explorer.
4. Confirm it directly contains `mods` and `config`.
5. Confirm the selected launcher version is `fabric-loader-0.19.3-26.2`.

A ZIP inside `mods` does not work. The pack must be extracted.

## Incompatible Mods

Do not combine files from different client variants. In particular:

- Voxy and Distant Horizons are separate client choices.
- Use only Minecraft 26.2 Fabric mods supplied with the selected pack.
- Do not replace Sodium or another dependency without checking the required version.

Restore a clean copy of the client ZIP if the pack was manually modified.

## Cannot Join The Server

Use this address without adding a port:

```text
katherine-thorough.tun.ply.gg
```

Then check:

1. The server host confirms that both Minecraft server and Playit are running.
2. Your exact Java username is on the whitelist.
3. You launched Minecraft 26.2 with Fabric Loader 0.19.3.
4. You are not using the same Minecraft account on another connected computer.

If the server log does not show a connection attempt, the issue is network or tunnel related. If it shows a mod mismatch, restore the correct pack.

## Mac Notes

- Use Mac No LOD for the safest experience.
- Use Mac Distant Horizons only on a capable Mac.
- Do not use the Windows Voxy pack on macOS.
- Reduce LOD distance and shader quality before raising the Java heap.

## Low-End Hardware

Start with the Universal Extreme Low End pack and `-Xmx3G` or `-Xmx4G`.

Recommended first changes:

1. Render distance: 4-6 chunks.
2. Simulation distance: 4-5 chunks.
3. Graphics: Fast.
4. Clouds: Off.
5. Particles: Minimal.
6. Shaders: Off.
7. Frame-rate limit: 30 or 60 FPS.

## Crash Reports

When asking for help, include:

- The exact client pack name.
- The exact red error message.
- `logs/latest.log` from that installation.
- The newest file from `crash-reports`, if one exists.

Do not share account tokens, launcher credential files, or the entire default `.minecraft` folder.

