import { createMemo, Match, Switch } from "solid-js";
import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";

export function LayoutKomorebiWidget() {
  const providers = useProviders();
  const layout = createMemo(
    () =>
      providers.komorebi?.currentMonitor.workspaces[
        providers.komorebi.currentMonitor.focusedWorkspaceIndex
      ]?.layout,
  );
  return (
    <GroupItem class="font-bold overflow-hidden">
      <Switch fallback={layout()}>
        <Match when={layout() === "bsp"}>[\\]</Match>
        <Match when={layout() === "vertical_stack"}>[V]=</Match>
        <Match when={layout() === "horizontal_stack"}>[H]=</Match>
        <Match when={layout() === "ultrawide_vertical_stack"}>||=</Match>
        <Match when={layout() === "rows"}>[==]</Match>
        <Match when={layout() === "grid"}>[]</Match>
        <Match when={layout() === "custom"}>Custom</Match>
      </Switch>
    </GroupItem>
  );
}
