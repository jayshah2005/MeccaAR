# 3D model

`Mecca.usdz` is the model used by the AR placement screen. RealityKit loads it
at runtime, corrects its exported standing axis, normalizes its visible height
to 30 mm, places its lowest point on the detected surface, and then applies the
user's size, X/Y rotation, and color controls. The placement default is 0.5,
making the character about 15 mm tall. The slider covers approximately 6–30 mm.
A small procedural character remains in code as a fallback if the bundled model
cannot load.

The source export was repaired before bundling to declare the material-binding
API required by USD validation and to remove a constant occlusion value that
could darken the character. The repaired package passes `usdchecker`.

See [`docs/THIRD_PARTY_ASSETS.md`](../../../docs/THIRD_PARTY_ASSETS.md) for
creator, source, license, modifications, and checksums.

Before public distribution, confirm that the uploader had the right to license
the character design and replace it with original production art if needed.
