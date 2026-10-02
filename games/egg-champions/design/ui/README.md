# Egg Champions: UI reference

Approved by the owner on 2026-10-02. The four `.dc.html` files are static
mockups at 1280 x 720. They are a visual reference for the coder, not code to
ship. Build the real UI in Roblox (ScreenGui) to match them.

| File | Screen |
| --- | --- |
| Main.dc.html | Main screen: world view with a slim top bar (coins, coins per click, world name, rebirths, badges), menu on the left, next-goal panel on the right, team of 3 at the bottom |
| EggShop.dc.html | Egg shop: one card per egg with price, the five pets and their odds, Hatch and Hatch x3 |
| Pets.dc.html | Pets and index: inventory grid with rarity stripe, tabs for My pets, Index, and Fruit Edition, detail panel with stats, moves, and Equip or Unequip |
| Battle.dc.html | Gym battle: HP panels for both active pets with type and team markers, arena, battle log, two move buttons with cooldown state, Give up |

## Rules the owner set
- There is no click button. Clicking or tapping anywhere on the world view
  earns coins, and the amount pops up where the player clicked.
- The look is not childish: dark flat panels (#12161F) with thin borders
  (#2A3242), small corner radius, Barlow and Barlow Condensed type or the
  closest Roblox font, uppercase labels, and gold (#E8B33A) as the only
  accent. Rarity colors: Common grey, Uncommon green, Rare blue, Epic
  purple, Legendary orange.
- Pets are colored blocks until the asset stage delivers models.
