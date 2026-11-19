import { expect, test } from "bun:test";
import { stageActionsOf } from "./StageActions";
import { AimKind } from "@domicile-desktop/manganese-window-management/tiled/aim";
import type { Aim } from "@domicile-desktop/manganese-window-management/tiled/aim";
import { Direction } from "@domicile-desktop/manganese-window-management/direction";
import { WindowAction } from "@domicile-desktop/manganese-window-management/window-state";
const rect = { x: 0, y: 0, width: 100, height: 100 };
test("window drops retain the SDK's exact nested-group node reference", () => {
  const actions: WindowAction[] = [], stage = stageActionsOf(action => actions.push(action), () => true);
  const node = { id: "app:target", up: 3 };
  stage.onDropOn("app:dragged", { kind: AimKind.Group, node, edge: Direction.Left, rect } as Aim);
  expect(actions).toEqual([WindowAction.WindowDroppedOn("app:dragged", node, Direction.Left)]);
});
test("a nested group can move along a strip with the public aim node", () => {
  const actions: WindowAction[] = [], stage = stageActionsOf(action => actions.push(action), () => true);
  const group = { id: "app:dragged", up: 2 }, node = { id: "app:target", up: 1 };
  stage.onGroupDropOn(group, { kind: AimKind.Strip, node, edge: Direction.Right, rect } as Aim);
  expect(actions).toEqual([WindowAction.GroupDroppedOn(group, node, Direction.Right)]);
});
