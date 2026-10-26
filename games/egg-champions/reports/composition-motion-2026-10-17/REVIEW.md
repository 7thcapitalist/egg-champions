# Composition and locomotion follow-up

Date: 2026-10-17, America/New_York. TEST only.

## Implemented

Rounded layered tree canopies; circular ponds with shore stones; a scenic return loop, seating and path lanterns; mill windows and foundation. Broader sea horizon and client-local visibility hide adjacent world geometry and signs. This does not modify world unlocks, collision or persistence.

Follower travel now controls facing and stride phase. Idle stops advancing the stride; turn interpolation eases changes; flight has a separate small lift/pitch, wings and tails. Two perpendicular walks were exercised using Humanoid MoveTo; movement-samples.json records position and facing through the turn and stop. The three hero followers were selected through a temporary client FollowerTeam attribute, without modifying inventory or saving a profile. Fixture state disappeared on Stop.

## Verification

861 Luau tests plus six self-tests pass; Selene zero warnings/errors; StyLua and both Rojo builds pass. ModelLibrary loaded 36/36 without placeholders. World part counts: Meadow 508, Coast 450, Volcano 343. In Meadow, 508 local parts remained visible and all 450/343 parts of the other worlds were locally hidden; their labels were also disabled. Screenshots use temporary overview cameras and matching biome lighting.

Desktop overview and gameplay captures inspected. Mobile landscape inspected at safe viewport 720x239. Portrait could not be validated: Studio reported Portrait and 390x844/320x720 device resolutions while its game viewport stayed landscape (842x308/720x239). Do not interpret this as portrait or physical-phone acceptance. The short viewport clips the lower action toolbar; this remains open.

## Economy decision

The published 300-player simulation is unchanged: 7.70h final gym and median 7 rebirths versus target 5. The reference Rare team has a 79% win rate at 5. Exploratory alternate policies were tested before changing difficulty: preserving and selecting the best owned matchup team versus a generic HP x Attack team radically changes early progression. An initial 300-player matchup experiment gave 3 rebirths and 8.69h, but also earned gym fees using the battle team. A corrected fee-switch experiment at 100 players showed the general HP x Attack policy can stall the first gym for hours because it ignores counters. These are sensitivity experiments, not a validated replacement for the original simulation. The experimental simulator was not shipped and no design target or difficulty was changed. The requested median-five target remains unresolved; weakening the final gym alone is not justified by these experiments.

## Honest visual review

Composition 3.5/5: cleaner horizon, rounded assets and a readable return loop, but broad empty areas and repetitive hub structure remain. Animation 3.5/5: distance-linked motion and facing improve travel, but no authored species-specific attack/hit animation or physical-device frame-time validation. Models and retained feedback remain 4/5 from v84 inspection; onboarding 3.5/5 for this review because the short landscape viewport clips controls and portrait could not be revalidated. No final art approval claimed.

Complete save/rejoin comparison, new pass purchases and physical phone performance remain independent untested launch requirements. Studio continues using a temporary profile because API access is disabled.

## Publication

Studio Output confirmed TEST v88 at 00:20:20 local. Cloud source verification is recorded separately in cloud-reopened.json. Full-module synchronization was initially rejected by automatic review; applying reviewed diffs limited to the visual changes succeeded. No production publication.
