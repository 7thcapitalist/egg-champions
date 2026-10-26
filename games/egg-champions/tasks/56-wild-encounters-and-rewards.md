# 56: Wild focus battles and collection rewards

Owner-directed addition, 2026-10-22. Keep existing saves and regular training.

- [x] Implement private optional timed wild encounters with server eligibility and cooldowns.
- [x] Grant a bounded active-only training boost on victory and one original capture prism attempt.
- [x] Add captured pets to the ordinary saved inventory/index without duplicate grants (real save/rejoin proof remains below).
- [x] Implement compact focus card, one local noncolliding wild visitor, reactions, prism and outcome.
- [x] Add permanent world/full collection bonuses and visible completion celebrations.
- [x] Add dismissible animated pass discovery and actual Roblox prices.
- [x] Run rule/integration tests, lint, build and updated economy analysis (pacing gate fails; see report).
- [ ] Review actual landscape/portrait interface and controls in engine.
- [ ] Publish and reopen TEST; confirm saved captures and bonuses after rejoin.

No native desktop control: owner requested stopping it in the previous turn.
No production publication. Automated tests do not certify real persistent saves.

Additional owner corrections: remove inventory-relative Legacy scaling; pet and variant powers stay fixed. At equal variants, every Epic must exceed the next egg Common/Uncommon and every Legendary must exceed the next egg Epic in Training Power, HP and Attack. Tests cover every configured adjacent egg pair. Victory coins are five base active-income seconds times monster strength, alongside a nonstacking 60s training boost.
