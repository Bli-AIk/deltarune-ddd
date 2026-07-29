# Kristal virtualkeyboard

This is an optional Kristal v0.10 library for Android builds. It provides a
touch joystick or button layout that feeds normal Kristal `Input` key events.

The library is enabled by default only when `love.system.getOS()` returns
`Android`. Desktop builds therefore keep their normal keyboard and gamepad
behavior. To test the controls on another platform, set `only_android` to
`false` in the `virtualkeyboard` section of `mod.json`.

Available configuration:

```json
"virtualkeyboard": {
    "enabled": true,
    "only_android": true,
    "show_on_start": true,
    "layout": "buttons",
    "toggle_key": null,
    "opacity": 0.78,
    "button_scale": 2.5,
    "button_radius": 38,
    "direction_area_radius": 122,
    "direction_deadzone": 0.2,
    "joystick_scale": 2.5,
    "joystick_radius": 108,
    "joystick_deadzone": 0.35
}
```

The default `buttons` layout uses a separated directional cross. On a wide
screen with enough border space, the controls are drawn in the left and right
side areas instead of over the game canvas, leaving about one button width at
the left outer edge and two at the right. Narrower windows keep the same
spacing inside the 640x480 canvas. Its touch area reads the horizontal and vertical axes
independently, so diagonal input, multi-touch, and sliding from one direction
to another are supported. The `z` button is vertically centered between `x`
and `c`. Action buttons can also be held together and can be changed by
sliding a finger to another button.

Set `layout` to `joystick` to use a directional joystick with the `z`, `x`
and `c` buttons. A mod can also call `VirtualKeyboard:setVisible(false)` or
`VirtualKeyboard:toggle()` at runtime. `toggle_key` is disabled by default;
Android Back is intentionally not used as the control toggle.

The adapter draws in Kristal's side areas when available, falls back to the
existing 640x480 game canvas with the same edge spacing, and converts touch
coordinates through Kristal's game scale and side offsets. It is not an API
compatibility layer for Kristal or LÖVE on Android.

## Attribution

The button and joystick artwork and the original touch-keyboard design were
provided by zzy (Bilibili UID `3546380257724712`) in the accompanying
`virtualkeyboardV3.5.7z` archive. The archive permits modification and
redistribution and requests credit. See the repository's `THIRD_PARTY.md`.
