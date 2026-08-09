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
