# Background assets — currently empty

The default pet world is transparent, so the Windows desktop remains visible in
`--desktop-mode`. Preview mode uses the flat backdrop from `config/app.json`.

No room/background PNG has been authored. The old preview floor guide is still
available through the legacy `StageGuide`, but it is hidden by default and is
not part of the persistent pet world.

When a background is added:

1. put it under `assets/backgrounds/`;
2. add a config entry/background scene;
3. keep the desktop-mode path transparent or explicitly define a non-transparent
   background policy;
4. do not bake the debug floor grid into the background art.
