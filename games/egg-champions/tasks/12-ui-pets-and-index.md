# Task 12: UI, pets and the index

## Goal
Where the player sees what they own, what they are missing, and chooses the
team of 3.

## Build
Read `design/ui/README.md` and `design/ui/Pets.dc.html` first. Match the
mockup.

1. `src/client/UI/Pets.luau`, using `Theme.luau`:
   - An inventory grid, one tile per owned pet, each with a rarity stripe in
     the rarity color and a variant marker for shiny and golden.
   - Three tabs: My pets, Index, and Fruit Edition.
   - Sort and filter controls: by rarity, by click power, by type, and by
     egg. Default sort is highest click power first, since that is the choice
     the player makes most.
2. The Index tab: every pet in config, one tile each, shown as seen or
   unseen. Normal, shiny and golden are tracked separately, so a tile shows
   three states. Per egg, show the completion count and the coin bonus a
   completed egg gives, from `index_egg_bonus`. A completed egg is marked.
3. The Fruit Edition tab: the pets whose config `edition` is set, on their own
   page. Fruit Edition is a collection tag, not a type or a rarity, so it
   filters and never affects stats.
4. The detail panel: the selected pet's stats (Click Power, HP, Attack,
   Speed), its type, rarity and role, both moves with the special's effect
   text from config, and `Equip` or `Unequip`. Show the variant multipliers
   applied, so a shiny pet's numbers match what the game uses.
5. Equip and Unequip send the remotes from task 08 and show the server's
   rejection reason when it refuses. The client never decides whether an
   equip is legal.

## Done when
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0,
      including tests for the sort and filter helpers.
- [ ] A test asserts the Index tab lists exactly the 30 pets in config, with
      the Fruit Edition tab listing exactly those whose `edition` is set.
- [ ] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] Side by side with `design/ui/Pets.dc.html`, the grid, tabs, rarity
      stripes and detail panel match.
- [ ] Equipping and unequipping updates the team bar on the main screen, and
      a fourth equip is refused with a readable message.
- [ ] Hatching a new pet marks it seen in the Index without a rejoin.

## Out of scope
Pet models and the shiny and golden visual effects, which are task 14. This
task shows the rarity stripe and a variant marker.
