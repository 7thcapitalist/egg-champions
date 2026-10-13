# Task 18: Game passes

## Goal
The four passes from the spec work, are checked on the server, and never
touch battle stats.

## Build
1. `src/server/Services/PassService.luau`:
   - Reads the four passes from `config/passes.json`: `2x_coins`,
     `auto_click`, `lucky_eggs`, `triple_hatch`. The pass ids come from
     config; the Roblox pass product ids live in one table in this module,
     since they are platform ids rather than game design.
   - Checks ownership with `MarketplaceService:UserOwnsGamePassAsync` on
     join, caches the result per session, and refreshes when the player
     finishes a purchase prompt.
   - Every check is wrapped in `pcall`. If the service is unreachable, treat
     the pass as not owned for now and retry; never grant a pass on an error,
     and never lose one the player owns by caching a failure as false.
2. Effects, each wired to the system that already owns the rule:
   - `2x_coins`: a factor in the pass multiplier that `Coins.perClick` takes
     as an input from task 03. The rule module stays unaware of passes.
   - `lucky_eggs`: sets `options.luckyEggs` on `Hatch.roll` from task 04.
   - `triple_hatch`: lets `ShopService` accept a count of three, charging
     three times the price.
   - `auto_click`: the server runs a click for the player on an interval
     while they are in game, at a rate held in a module constant. The server
     drives it, not the client, so it cannot be sped up from outside.
3. No pass affects battle HP or Attack. This is a spec rule, so it gets a
   test that would fail if a pass were ever added to the battle path.
4. The main screen shows which passes are active, and offers the purchase
   prompt for the ones that are not, using the mockup's badge area in the top
   bar.

## Done when
- [x] `python factory/tools/run_tests.py games/egg-champions` exits 0,
      including:
      - a test that the pass ids handled equal the ids in
        `config/passes.json`, so a new pass cannot be half-implemented;
      - a test that `2x_coins` exactly doubles coins per click at 0 and at 3
        rebirths;
      - a test that `lucky_eggs` doubles Epic and Legendary odds and the
        table still sums to 1;
      - a test that no pass changes any value on the battle path, by running
        a seeded battle with every pass on and off and asserting identical
        results.
- [x] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl`
      succeeds.
- [x] `grep -rn "UserOwnsGamePass" games/egg-champions/src` matches only
      `src/server`.
- [x] `selene games/egg-champions/src` and
      `stylua --check games/egg-champions/src` pass.

## Needs human or playtester
- [ ] In the test place with a test pass granted: 2x Coins doubles the
      displayed coins per click, Triple Hatch offers and charges for three,
      Lucky Eggs shows the improved odds, and Auto Click earns while idle.
- [ ] Owning no pass leaves the game fully playable.

## Out of scope
Pricing and the store listing, which are the publisher stage. This task needs
the pass ids to exist; the owner creates them.
