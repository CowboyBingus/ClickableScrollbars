# Making the item-select scrollbars clickable

The tabs with a scrollable list (Primary, Secondary, Throwable, Armor, Helmet,
Cape, Emote, Victory Pose, Player Card, Title and Career) accepted only the
mouse wheel: clicking the track did nothing, and there was no way to drag the
list. This is the record of what the menus actually are and why the shipped
mod takes the shape it does.

## The bars are native, not XAML

The menus are data-driven XAML, and the affected scrollbars resolve their
templates through this chain:

```
ListBox  ->  Template = ListBox_Template_Default
             ScrollViewer Template = ScrollViewer_Template_WarbondsTab
               ScrollBar Template = ScrollBar_Template_Default
```

Every shipped copy of `ScrollBar_Template_Default` puts only a `Thumb` inside
`Track`; a WPF-style `ScrollBar` pages only when the track also holds decrease
and increase `RepeatButton`s, so the track is inert by construction.

A data-only fix was implemented and deployed first: the three dictionaries that
hold the template (`range_templates`, `acquisitions_resources_2`,
`component_bundle`) were overridden to add two invisible `RepeatButton`s using
the game's own `ScrollBar.PageUpCommand` / `ScrollBar.PageDownCommand` pair.
The override deployed and loaded (the running process contained the edited
markup) and still did nothing, because the visible bars are not drawn by those
templates at all:

* The Career statistics bar is a uniform `#A6A6A6` thumb about 10 design px
  wide; the Armory item-grid bar is 13 screen px wide with yellow end caps.
* Neither bar reacts to hover, while every shipped template brightens or widens
  its thumb on hover.
* A scan of the running process for `TargetType="ScrollBar"` returns only the
  three data files above plus the information-terminal pair, so no data-visible
  template could render the observed bars.

The consequence is that the item-grid and Career bars are drawn by the engine's
native UI, which no resource override reaches.

## What is left, given loader-only mods

The mod must stay a plaintext Lua resource delivered by Bingus Shared Loader:
no DLL, no executable-memory patch, no system hook and no game-file override.
Inside that boundary the only lever is the input the game already implements.
The mod therefore:

1. **Detects the bar from the rendered frame.** A strip of the screen around the
   cursor is copied with GDI (`BitBlt`) and scanned for the measured bar shape:
   vertical runs of neutral grey, uniform along their length, clearly darker
   panel beside them, the click pixel itself dark (the invisible track, not list
   content), and the bar's column within 12 px of the cursor.
2. **Masks only what the pointer makes unreadable.** The pointer is drawn as a
   coloured sprite about 100 px across with a bright core and a mild neutral
   halo. Inside its box, a pixel that is coloured or brighter than the accepted
   window is treated as hidden and bridged, while a pixel that still reads as
   dark panel ends the run, so a thumb under the pointer keeps its true extent.
   A thumb end hidden by the sprite is reconstructed from the tracked height.
3. **Turns clicks and drags into wheel input.** A press on the track moves the
   thumb so its centre lands under the pointer; a press on the thumb grabs it
   and the thumb then follows the pointer one-to-one; a press elsewhere does
   nothing. Notches are sent with `SendInput`, one event per notch, on the frame
   the pointer produced them.

## Why input is never queued

An earlier build queued notches and drained them on a timer. Three symptoms came
from that single decision: the thumb trailed the pointer during a fast drag
(the drain rate could not follow the hand), it kept moving after the pointer
stopped (the queue finished draining), and repeated settle passes nudged the bar
in 32 ms steps. The shipped design removes the queue entirely and adds two
rules:

* Every notch is sent on the frame that produced it, so the input rate is the
  pointer's rate.
* A settle correction requires the thumb to have stopped, a whole notch that is
  *smaller* than the residual it removes, and an unused correction budget. A
  residual inside half a wheel step is accepted, and a multi-notch jump that
  moved nothing is reported as `no_response` instead of being chased.

Whole wheel notches quantise the aim, so half a wheel step is the best a click
can land. On the test machine one notch is about 13 px, which puts the thumb's
centre within about 6 px of the pointer.

## Measured costs

Measured on a 3440x1440 desktop with the same code the addon runs in game:

| Measurement | Value |
|---|---|
| Desktop device context copy, 24x320 up to 96x920 | ~9 ms, independent of strip size |
| Game window device context copy, 96x920 | 0.03-0.2 ms |
| Pixel scan, 96x920 / 40x840 | 5.4 ms / 2.0 ms |

The copy therefore dominates and its cost is fixed per call, not per pixel.
Captures prefer the game's own window device context, cross-check it against the
desktop copy on the first capture of a session, and fall back permanently (with
`capture_source` in the log) when a window copy is black or clipped. Nothing is
captured while a drag is in progress, so the steady-state cost of dragging is a
few arithmetic operations per frame.

## Geometry follows the display

Every pixel constant in the detector was measured on a 1440 px tall viewport:
the bar is about 13 px wide, the pointer sprite about 100 px across, the pointer
halo about 70 px, and one wheel notch about 13 px. The game scales its interface
with the viewport height (the Career thumb is roughly 440 design pixels, 586 px
at 1440p), so those constants cannot stay fixed on another display. Two
ship-tested failures followed from that:

* At 2160p the same thumb would be about 880 px tall, while a 460 px capture
  window only holds runs up to 865 px, so the Career bar would not be
  recognised at all.
* The pointer sprite would grow to about 150 px, slightly wider than the 144 px
  mask box, so the covered middle of a thumb could be read as background.

Version 2.2 therefore treats the measured values as the *reference* for a
1440 px viewport and multiplies the geometry by `display_height / 1440`, taken
from the game window's client area on the first press and re-checked on every
later press. The resulting values are:

| Viewport height | Capture window | Strip width | Pointer box | Widest bar | Shortest bar | Wheel-step seed |
|---:|---:|---:|---:|---:|---:|---:|
| 1080 | 345 | 72 | ±54 | 21 | 33 | 9.8 px |
| 1440 | 460 | 96 | ±72 | 28 | 44 | 13 px |
| 2160 | 690 | 144 | ±108 | 42 | 66 | 19.5 px |

The 1440p row is byte-identical to the values earlier versions shipped, so an
existing install behaves exactly as before. Brightness thresholds, timing and
the wheel-step *range* are deliberately not scaled: luma is not a length, and
the calibration range is widened by the same factor separately. Values written
into the ini stay absolute device pixels and are never scaled, and
`scale_geometry=0` turns the whole transform off.

Two further guards cover the cases the scale alone cannot: a thumb taller than
the strip, or a track click far from it on a long list, now triggers one retry
with a doubled capture window (`window_max` caps it, `wide_retries` counts it);
and a scale change resets the tracked thumb, the cached bar column and the
learned wheel step, because all three were measured in the old geometry.

## What is verified offline

The detector is replayed against captured frames of the live Armory and Career
bars: clicking the Armory thumb is a grab with the sprite over it, clicking the
Career thumb is a grab, and clicking above or below either bar is a track press
whose pixel is the dark panel. Runtime tests drive the addon against a scripted
platform for same-frame emission, one-to-one dragging, bounded corrections,
`no_response`, pointer teleports, error tolerance and the log contents. A model
whose list eases towards its target measures a matched click landing 2 px from
the pointer with no correction, and a game whose wheel step is 1.7x the estimate
being corrected by a single nudge to 4 px.

The remaining visible difference from a native scrollbar is the game's own
easing: wheel input sets a target that the list animates towards, so during a
fast drag the thumb trails the target by roughly *speed x the animation time
constant* regardless of how input is delivered. Removing that would require
injecting ahead of the pointer and retracting when the pointer stops, which is
the overshoot-and-correct behaviour this design exists to remove.

In-game confirmation of the released build is still pending; `docs/VALIDATION.md`
records what has and has not been run.
