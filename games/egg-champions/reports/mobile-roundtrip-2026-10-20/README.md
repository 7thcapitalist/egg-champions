# Mobile and TEST work in progress

Updated 2026-10-21. This report is not release approval.

The battle log now measures wrapped lines using the actual font and available
width. Portrait observations showed full long messages in 34px rows, with
TextFits true, after real attack and heal inputs. Short landscape hides the
log intentionally to preserve the combat scene.

The owner requested smaller, lighter buttons and identified iPhone 17 as their
device. Landscape is the primary acceptance orientation. Studio currently
offers iPhone 17 Pro, not the exact base iPhone 17. Its landscape observation
used a 749x381 effective viewport with device safe areas; it is a proxy, not a
physical-device result.

Current UI changes: 84px compact menu width, 48px mobile move height (44px on
very short screens), bounded horizontal move width, compact surrender, 1px
button borders and 8px corners. The latest HUD revision centres the pet strip
between movement/jump controls and raises the left menu when chat is closed.

Landscape phones below 450px height now use side status panels and retain a
48px scrolling log above 190x48 move buttons. At 749x381, creatures measured
173x173 instead of the previous approximately 35px. The final side panels fit
the complete Golden Puddlet name, HP and team indicators. The final original
capture is `iphone17-landscape-battle-final.jpg`. The final attack run reached
turn 3 with all log rows fitting; its second enemy attack fainted the active
pet before the requested heal could execute. Earlier successful nonzero healing
must not be confused with that final run. See `observations-revised.json`.

The isolated QA session was stopped and its simulator reset to the default
viewport, keeping shipping LandscapeSensor orientation. Attempts to dismiss the
unconfirmed upload did not yield a confirmed cancellation or success. The TEST
publication outcome remains unknown and must be checked before another publish.

Observed on the revised UI before the final HUD positioning change: short
567x237 attack and heal reached turn 3; portrait 319x719 retained all log text
and used 143x48 move buttons plus 100x44 surrender. A real UI hatch spent 50
temporary coins and added Leafpup; Best Coins then equipped the third pet.
Journey target opened the egg shop. The Journey entry was opened through its
runtime module after automated top-bar clicks did not reliably open it, so
the top-bar entry itself remains unverified.

The initial desktop and portrait captures predate later source changes.
`observations-in-progress.json` records initial desktop results only. Neither
those captures nor this partial revised run satisfy the complete current mobile
matrix. Original JPEG captures remain unmodified. `checks-current.json` binds
the latest normal build and actual local checks. Missing release evidence stays
null in the release manifest.

## TEST publication and saves

The normal mobile-roundtrip-final-2026-10-20 candidate was opened separately
from seeded QA. All 145 compiled sources matched the XML build reference,
including the server/client root scripts; BetaQA and fixture scripts were
absent. Publish As selected Egg Champions Test, but Studio remained at Upload
in progress without a success message or place/version identity. Publication
is unknown, not passed. This candidate also predates the owner's button
feedback. Do not use it as certification of the latest UI.

No real DataStore before/release/re-entry snapshots have been obtained. The
local observations used explicitly guarded temporary profiles, never persistent
player data. Exact saves, published source reopen, physical touch, measured
network impairment, multiplayer, natural gyms 2+ progression and purchase
completion remain pending. The owner has an iPhone 17 available. TEST only is
authorized; no production publication or spending was performed.

## Next acceptance steps

1. Finish landscape review on the latest normal build and repeat the current
   desktop, short landscape and portrait action matrix with original captures.
2. Resolve the Studio upload outcome, publish the latest normal candidate to
   TEST, reopen and compare all compiled sources and exact place version.
3. On the owner's iPhone 17 in landscape, exercise movement/jump, hatch, team
   selection, Journey, attack/heal and a normal leave/rejoin without purchases.
4. Capture all 12 saved fields before exit, actual saved/released evidence,
   and a new session on the same TEST version. Run beta_checks.saves.
5. Obtain measured impaired-network and remaining release evidence; rerun
   gates and record only real results. Task 54 remains running.
