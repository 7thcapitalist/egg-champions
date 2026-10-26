# Tiered prism follow-up, 2026-10-22

Supersedes the task 56 README's free encounter-bound prism and uniform first-egg
pool. No TEST publication has been performed for this candidate.

Three saved consumables: Basic 1x, Refined 3x, Aurora 8x. Common through Legendary
base capture chances are 75/45/20/5/1 percent, with additional difficulty for
later origin worlds and second-egg species, capped at 90 percent. The target
card shows its numeric chance; the pack shop discloses all 30 species' chances.
One prism is consumed before a server roll, at most once per defeated encounter.
No stock leaves the opportunity intact. A successful capture enters the regular
inventory and normal index. No dynamic Legacy scaling was restored.

Each training area uses its own weighted rarity pool, drawing from both local
eggs. Advanced areas have better rare/Epic/Legendary weights. Eight percent of
encounters use an adjacent area's species. A victory has an 8 percent chance to
drop one prism, with better quality distributions in later origin areas.
Basic is also available for 500 earned coins; new/migrated players get one once.

Creator Hub and Studio MarketplaceService both confirmed TEST products:

| Tier | Quantity | Product ID | Base Robux |
| --- | --- | --- | --- |
| Basic | 10 | 3721209790 | 19 |
| Refined | 5 | 3721210003 | 49 |
| Aurora | 3 | 3721210181 | 99 |

Only TEST universe 10769019206 offers these IDs. Managed pricing is disabled.
The client fetches actual Roblox prices; a failed lookup is cached until the
shop is reopened, avoiding repeated requests on training state updates.
No Robux purchase was performed. Product creation is not a game publication.

Schema 6 migrates existing saves without changing pets, coins or progress.
Earned and paid balances are separate and survive rebirth. PolicyService must
explicitly allow paid random items before paid balances are usable or packs
offered. Earned stock is consumed first. ProcessReceipt persists stock plus the
purchase ID before acknowledgement. Failed saves return NotProcessedYet; retries
flush the same grant. Temporary profiles never acknowledge paid receipts.

## Observed validation

909 shared Luau tests, 6 runner checks and 137 Python tests passed. The fixtures
execute the real wild/training/purchase services and persistent-save coordinator,
covering unavailable policy, unknown products, temporary storage, outages,
session loss, callback replay, lost acknowledgements, concurrent callbacks,
rejoin and duplicate receipt handling. These are simulated stores, not real saves.
Selene has zero errors/warnings, formatting and normal Rojo builds pass.

Actual Studio QA used an iPhone 17 Pro preset in LandscapeLeft, logical viewport
750x381, as a proxy for the owner's iPhone 17. Joystick drag moved the avatar
24.1999 studs; keyboard movement moved it 24.6074 studs; a free-area touch-style
drag changed camera direction by 86.159 degrees. Native TouchGui was present
and ClickLayer absent. These are simulated inputs, not physical iPhone proof.

The actual temporary-profile flow bought one Basic for coins (stock 1 -> 2),
hatched Leafpup while training (four pulses during the hatch observation), won
against Zapmoth (125 HP, strength 1.25, 250 victory coins), captured it (stock
2 -> 1, pet count +1, normal Zapmoth index entry), and rejected replay without
another stock change. The whole observed flow recorded 38 training pulses.
The shop rendered 30 odds rows and correctly disabled paid purchase for this
temporary session. A real pointer click changed Basic to Refined, showing zero
stock and GET PRISMS, with a 192x44 selector. Screenshots and raw observations
are saved beside this report.

The runtime source hash list identifies that exact session. A later UI-only
follow-up added price failure caching; gameplay, inventory and receipt modules
are unchanged. The final candidate is separately bound by candidate-validation.json
and its complete Studio Edit hash comparison. Play-only QA helpers were removed
by stopping Play; none are included in the normal candidate.

## Remaining release work

The Studio Edit session is still based on published place version 105. Publish
the prepared candidate to TEST, reopen it, and verify the version. Physical
iPhone touch, real save/reentry, real-client multiplayer and impaired-network
checks remain outstanding. There is no authorization to spend Robux on tests.

The regenerated canonical passive forecast still misses gym pacing and gym 2/3
rebirth targets. It excludes optional wild wins, captures and prism purchases.
The factory is not certified launch-ready; no release gate was bypassed.
