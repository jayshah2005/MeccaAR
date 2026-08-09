# 3D model

`Mecca.usdz` is the classic model. `MeccaPose09.usdz` through
`MeccaPose19.usdz` are selectable alternatives. RealityKit loads the selected
pose at runtime, corrects its exported standing axis, normalizes its visible
height to 30 mm, places its lowest point on the detected surface, and then
applies the user's size, X/Y rotation, and color controls. The placement slider
covers approximately 20–35 mm. A captured face photo can be rendered as a small
unlit plane over the character and persisted for other players.
A small procedural character remains in code as a fallback if the bundled model
cannot load.

Every source export was repaired before bundling to declare the material-binding
API required by USD validation and remove a constant occlusion value that could
darken the character. All bundled packages pass `usdchecker`.

See [`docs/THIRD_PARTY_ASSETS.md`](../../../docs/THIRD_PARTY_ASSETS.md) for
creator, source, license, modifications, and checksums.

Before public distribution, confirm that the uploader had the right to license
the character design and replace it with original production art if needed.
