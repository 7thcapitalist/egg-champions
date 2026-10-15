# Task 35: HUD clear of Roblox's own buttons and chat, with click feedback

## Goal
Playtest: the coin counter and "+N PER CLICK" sit under Roblox's top-bar
buttons (logo, menu, chat, voice), so the most important number cannot be
read; the Roblox chat window opens over the left menu and eats its clicks;
the first goal line is cut off ("Open EGGS and hatch your first..."); no
visible feedback on clicks.

## Build
1. Lay out the HUD from GuiService.TopbarInset (and re-layout on its
   change): coins start right of TopbarInset.Min.X + 8 px or the bar starts
   below TopbarInset.Max.Y. Same for EggShop and Pets panel tops.
2. Menu clear of the chat area: vertically centered on the left edge below
   45% of the screen height, or configure TextChatService's
   ChatWindowConfiguration so the chat window sits bottom-left and the menu
   avoids that rect. HudLayout treats the chat rect as reserved.
3. Goal card text fits: tutorial and goal lines at most 28 characters, or a
   third line; spec that every card text fits the goal width at its size.
4. Click feedback: each credited click shows a "+N" float at the cursor,
   drawn above the HUD, and pulses the coin counter; a short coin sound.
5. HudLayout specs take the top-bar inset and chat rect as inputs; no
   overlaps at 808 x 432, 1092 x 432, 1280 x 720, 1920 x 1080.

## Done when
- [ ] `python factory/tools/run_tests.py games/egg-champions` exits 0.
- [ ] `selene games/egg-champions/src` and `stylua --check games/egg-champions/src` pass.
- [ ] `rojo build games/egg-champions -o games/egg-champions/build/game.rbxl` succeeds.
