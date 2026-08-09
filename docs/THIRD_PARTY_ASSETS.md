# Third-party assets

## Meccha Chameleon white character

- Creator: **samkar_09**
- Source: [Sketchfab model page](https://sketchfab.com/3d-models/meccha-chameleon-white-character-de8cbf6d00e6490bbbead170d85ab1e8)
- License listed by the source: [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/)
- Original download SHA-256: `33f55809b537b3015301b50865f8b0eb34d82fe429f89d363f331b81f9c20867`
- Bundled USDZ SHA-256: `20e5ae022ec5a9a37a4b7c30ffb4d056a509fd59803286430bb6e751e94377f4`

Changes made for the app:

- declared USD `MaterialBindingAPI` on the mesh so the package passes USD validation;
- removed a constant occlusion input that could incorrectly darken the model;
- corrected the model's exported standing axis at runtime;
- normalized visible bounds and surface alignment at runtime;
- replaced model materials at runtime when the player selects a color;
- generated collision shapes at runtime for future interactions.

The model page identifies this as a character from *MECCHA CHAMELEON*. A CC
license from an uploader does not by itself establish ownership of the
underlying character design. Verify those rights or replace this prototype
asset with original production art before public distribution.

## Meccha Chameleon poses 9–19

- Creator: **adu2763**
- License embedded in each USDZ: [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/)
- Sources: [Pose 9](https://sketchfab.com/3d-models/meccha-chameleon-pose-9-91a07a3bd9214feda94962f24b7cfc74), [Pose 10](https://sketchfab.com/3d-models/meecha-chameleon-pose-10-dad05eafa4164ee28571d4bfc0ef1483), [Pose 11](https://sketchfab.com/3d-models/meccha-chameleon-pose-11-2aa0fbc64d754957ace9f1a50e6927fb), [Pose 12](https://sketchfab.com/3d-models/meccha-chameleon-pose-12-e2b63b2302cb4dd098824bc81dc864ec), [Pose 13](https://sketchfab.com/3d-models/meccha-chameleon-pose-13-76de676fc2fb4ee082e15a2b00124398), [Pose 14](https://sketchfab.com/3d-models/meccha-chameleon-pose-14-991d86ece16246f5ad6c1246d6dafaab), [Pose 15](https://sketchfab.com/3d-models/meccha-chameleon-pose-15-af1f08caa02840638923d937e3051735), [Pose 16](https://sketchfab.com/3d-models/meccha-chameleon-pose-16-a3289ab95c614d898daac705b95d0e43), [Pose 17](https://sketchfab.com/3d-models/meccha-chameleon-pose-17-176f02075a484d7cad5c74300f0edc27), [Pose 18](https://sketchfab.com/3d-models/meccha-chameleon-pose-18-21e60ca08a3f4ffb8d3903af7bb04617), [Pose 19](https://sketchfab.com/3d-models/meccha-chameleon-pose-19-183d45cb42a147f1ba68653461f1af9e)

The pose exports received the same material-binding and occlusion repairs as
the classic model. Their visible bounds are normalized at runtime, and all 11
repaired packages pass `usdchecker`.
