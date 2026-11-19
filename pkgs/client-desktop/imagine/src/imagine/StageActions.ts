// Adapted from Manganese f6dc5b2b625c24bd2b00bed9910bc48241fea0ba.
// Preserve the public Aim node reference, including nested group depth.
// Copyright 2026 Connor Prussin; MIT (LICENSE). No private package imports.
import type { Direction } from "@domicile-desktop/manganese-window-management/direction";
import type { Geometry } from "@domicile-desktop/manganese-window-management/placement";
import type { Spot } from "@domicile-desktop/manganese-window-management/pointer-warp";
import type { Rect } from "@domicile-desktop/manganese-window-management/rect";
import type { Aim } from "@domicile-desktop/manganese-window-management/tiled/aim";
import { AimKind } from "@domicile-desktop/manganese-window-management/tiled/aim";
import type { NodeRef } from "@domicile-desktop/manganese-window-management/tree/path";
import { WindowAction } from "@domicile-desktop/manganese-window-management/window-state";

export const stageActionsOf = (
  act: (action: WindowAction) => void,
  pointing: (at: Spot) => boolean,
) => ({
  onBarPress: (id: string) => {
    act(WindowAction.WindowBarPressed(id));
  },
  onClose: (id: string) => {
    act(WindowAction.WindowClosed(id));
  },
  onDescription: (window: string, description: string) => {
    act(WindowAction.BrowserDescribed(window, description));
  },
  onDismiss: (id: string) => {
    act(WindowAction.ScratchpadDismissed(id));
  },
  onDrop: () => {
    act(WindowAction.WindowDropped());
  },
  onDropOn: (id: string, aim: Aim) => {
    switch (aim.kind) {
      case AimKind.Screen: {
        act(WindowAction.WindowDroppedOnScreen(id, aim.name));
        break;
      }
      case AimKind.Group:
      case AimKind.Strip:
      case AimKind.Tab:
      case AimKind.Window: {
        act(WindowAction.WindowDroppedOn(id, aim.node, aim.edge));
        break;
      }
    }
  },
  onFloat: (id: string) => {
    act(WindowAction.WindowFloated(id));
  },
  onFocusRequest: (id: string) => {
    act(WindowAction.FocusRequested(id));
  },
  onFullscreen: (id: string) => {
    act(WindowAction.WindowFullscreened(id));
  },
  onGrab: (id: string) => {
    act(WindowAction.WindowGrabbed(id));
  },
  onGroupClose: (group: NodeRef) => {
    act(WindowAction.GroupClosed(group));
  },
  onGroupDropOn: (group: NodeRef, aim: Aim) => {
    switch (aim.kind) {
      case AimKind.Screen: {
        act(WindowAction.GroupDroppedOnScreen(group, aim.name));
        break;
      }
      case AimKind.Group:
      case AimKind.Strip:
      case AimKind.Tab:
      case AimKind.Window: {
        act(WindowAction.GroupDroppedOn(group, aim.node, aim.edge));
        break;
      }
    }
  },
  onGroupFloat: (group: NodeRef) => {
    act(WindowAction.GroupFloated(group));
  },
  onGroupFullscreen: (group: NodeRef) => {
    act(WindowAction.GroupFullscreened(group));
  },
  onGroupGrab: (group: NodeRef) => {
    act(WindowAction.GroupGrabbed(group));
  },
  // Only when the pointer actually moved. A window sliding under a still
  // pointer also fires `pointerover`, and following it would steal focus. See
  // `usePointerWarp`.
  onHover: (id: string, at: Spot) => {
    if (pointing(at)) {
      act(WindowAction.WindowHovered(id));
    }
  },
  onIcon: (window: string, icon: string) => {
    act(WindowAction.BrowserIconChanged(window, icon));
  },
  // In page pixels, so a float can be dragged to another screen; see
  // `floatDragged`.
  onMove: (id: string, x: number, y: number) => {
    act(WindowAction.WindowMoved(id, x, y));
  },
  onNewTab: (id: string) => {
    act(WindowAction.NewTabPressed(id));
  },
  onPageFullscreen: (id: string, fullscreen: boolean) => {
    act(WindowAction.PageFullscreened(id, fullscreen));
  },
  // Converted to the float's screen's pixels.
  onResize: (id: string, box: Rect, on: Geometry) => {
    act(
      WindowAction.WindowResized(id, {
        ...box,
        x: box.x - on.screen.x,
        y: box.y - on.screen.y,
      }),
    );
  },
  onSelect: (id: string) => {
    act(WindowAction.WindowSelected(id));
  },
  // The tiling is laid out in the screen's workspace box, so a dragged pixel
  // is a share of that.
  onStretch: (id: string, edge: Direction, by: number, on: Geometry) => {
    act(WindowAction.WindowStretched(id, edge, by, on.workspace));
  },
});
