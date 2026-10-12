# Asset manifest

`manifest.json` lists the 36 approved models for Egg Champions: 30 pets and 6 eggs.
There is one entry per pet id in `config/pets.json` and one per egg id in `config/eggs.json`.

Each entry has:
- `id`: the pet or egg id from config.
- `kind`: `pet` or `egg`.
- `source_model`: the model name in the "Egg Champions Test" place. Pets live in `Workspace.Pets_Selected`, eggs in `Workspace.Eggs`.
- `mesh_asset_id` and `texture_asset_id`: the MeshPart `MeshId` and `TextureID` (`rbxassetid://<id>`).
- `height_studs`: the target height the model was scaled to. `null` means not recorded.
- `status`: `ready`, `pending_studio_read`, or `needs_texture_save`.
- `notes`: known flaws, one line.
- `needs_texture_save`: only on entries whose texture is not saved as an asset yet.

## How the ids were obtained

- World 1, 2 and 3 pets: copied from the manifest tables in `notes/pets-world-1-batch.md`, `notes/pets-world-2-batch.md` and `notes/pets-world-3-batch.md`. Those agents read the ids from the MeshPart of each selected attempt. Heights and flaws come from the same tables.
- Eggs: copied from the egg batch report (selected attempt per egg). That report is not in the repo. Egg heights were not recorded.
- Leafpup, Emberkit, Abacatudo, Bananao and Moranguete: their models were chosen before the batches, and their ids are not written in any file. They are marked `pending_studio_read`. Leafpup and Emberkit heights are the model test 2 measurements. The three Fruit Edition heights are the 8 stud design target.

Kelpony_3 is in the manifest as approved, but its batch verdict was fail (no kelp mane). Driftgull_3 is scaled by wingspan, so it is only 2.15 studs tall.

## Entries that still need a Studio step

| Id | Source model | Step |
| --- | --- | --- |
| leafpup | Leafpup_B | Read MeshId, TextureID and height |
| emberkit | Emberkit_A2 | Read MeshId, TextureID and height |
| abacatudo | Abacatudo_S2 | Read MeshId, TextureID and height |
| bananao | Bananao_3 | Read MeshId, TextureID and height |
| moranguete | Moranguete_R4 | Save the repainted face texture as an asset, then read MeshId, TextureID and height |
| meadow, forest, shell, storm, ember, magma | the six egg models | Read height (ids are already filled in) |

After a Studio read, replace `pending_studio_read` with the ids, set `status` to `ready`, and drop `needs_texture_save` once the texture is saved.
