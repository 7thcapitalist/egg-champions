# Visual quality contract

Read this before planning art, UI, effects or onboarding. Technical validity is
necessary, but it does not prove appealing art or a clear first session.

## Reference study

Refresh a small reference study at the start of a new game. Record date,
device/region, source URLs, actual observed features and inference separately.
Use current Roblox Charts, the user's reference and two games relevant to the
genre. Do not claim to have played a game based on its promotional image.
Popularity is evidence of reach, not proof that copying a feature causes success.
All models, characters and world compositions must remain original.

## Required design artifacts

- Art bible: silhouette rules, limited palette, materials, scale, lighting,
  camera, UI type sizes, rarity treatment and three explicit anti-examples.
- World sheet per biome: focal landmark, foreground/midground/background,
  arrival sightline, traversable loop, safe interaction zones and ambient motion.
  Changing palette alone does not make a new world.
- Asset contact sheet in the actual engine: front, side, back, portrait and
  gameplay scale. Face must remain legible at card size. Check all variants.
- Animation sheet: idle, travel, attack, hit, faint, hatch. State transitions
  should ease; feet should not visibly skate and flying creatures need lift.
- Effect matrix: action, anticipation, impact, decay, audio, rarity escalation,
  mobile budget, cleanup and reduced-motion behavior. Effects must explain an
  event and leave the target and buttons visible. No permanent screen flashes.
- Onboarding walkthrough: fresh profile, first reward, equip, visible increase,
  next goal, first meaningful choice. One objective and one reachable action at
  a time. Check touch and mouse. Never obscure the action with tutorial text.
- Collection value policy: every rarity remains useful or has an explicit
  retirement path. Test old rare versus next common, duplicate and variant,
  rebirth and final world. UI and server must use the same rules.

## Review standard

Review desktop and phone-sized views for each biome and main interaction.
Score composition, models, animation, feedback and onboarding from 1 to 5:
1 broken, 2 placeholder/unclear, 3 functional but needs polish, 4 polished and
readable, 5 distinctive and consistently finished. A reviewer must describe
what they actually saw, not score from code. Capture evidence and note device,
Studio versus published client, source hash, performance limits and unresolved
issues. Require at least 4 in each area before calling visual quality approved.
An automated evidence check validates completeness and freshness only; it cannot
decide whether an image is attractive. User feedback overrides internal scores.

For phone UI review, record both requested device resolution and the actual
camera/ScreenGui dimensions. A portrait device setting with a landscape capture
is not portrait evidence. Include a short landscape viewport (720x239), portrait
320x720 and 390x844, and the maximum unlocked menu. Exercise opening, closing,
hatching and equipping with real UI input; rectangle tests alone are insufficient.
If a panel needs scrolling, keep Close reachable and reveal the tutorial action
inside the clipped viewport. Distinguish custom Studio resolution from mobile
device emulation and physical-phone performance.

Use `python factory/tools/quality_review.py <game-dir> <review.json>` to check a
review. Missing, stale, blocked or incomplete reviews fail. This is a separate
quality check; it never marks unfinished factory stages passed.

## Reference snapshot: 2026-10-16

[Roblox Charts](https://www.roblox.com/charts), Computer / United States view,
Top Playing Now explicitly covers all devices and locations. Observed order:
Steal An Egg (1.5M), Brookhaven (464.4K), RIVALS (344.2K), Adopt Me (257K),
Break and Steal an Egg (213.3K), Murder Mystery 2 (208.9K), 99 Nights (204.8K).
Counts are one snapshot and must not be treated as permanent rankings.

[Steal An Egg](https://www.roblox.com/games/107778070777162/Steal-An-Egg):
official page describes hatch, pets earning money, speed training and upgrades.
Observed promotional art has a large readable creature silhouette, clear face,
broad color regions, exaggerated egg and strong foreground/background separation.
This is promotional imagery, not a measured in-game performance review.

[Pet Simulator 99 developer update](https://www.biggames.io/post/pet-simulator-99-update-7):
documented area quests, mastery perks and distinct area activities. Design
inference: a map should offer legible objectives and rewards, beyond scenery.

[Grow a Garden](https://www.roblox.com/games/126884695634066/Grow-a-Garden):
official description presents a short plant/grow/harvest loop and visible
collectibles. Design inference: first-session instructions should name concrete
actions and immediately show their result.

[Steal a Brainrot](https://www.roblox.com/games/109983668079237/Steal-a-Brainrot):
official description combines collection, income and social interaction. Use
this as a reference for visible collection identity, not as a requirement to
copy stealing or monetize frustration.
