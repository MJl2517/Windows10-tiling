import { createMemo } from "solid-js";
import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";

export function FocusedWindowTitleKomorebiWidget() {
  const providers = useProviders();
  const isCurrentMonitor = createMemo(
    () =>
      providers.komorebi?.focusedMonitor === providers.komorebi?.currentMonitor,
  );

  const title = createMemo(
    () =>
      providers.komorebi?.focusedWorkspace.maximizedWindow?.title ??
      providers.komorebi?.focusedWorkspace.tilingContainers[
        providers.komorebi?.focusedWorkspace.focusedContainerIndex
      ]?.windows[0]?.title ??
      providers.komorebi?.focusedWorkspace.monocleContainer?.windows[0]
        ?.title ??
      "-",
  );

  return (
    <GroupItem class="text-ellipsis whitespace-nowrap max-w-[200px] 2xl:max-w-[350px] lg:max-w-[200px]">
      <span
        title={title()}
        classList={{
          "text-rose-pine-muted hover:text-inherit": !isCurrentMonitor(),
        }}
      >
        {title()}
      </span>
    </GroupItem>
  );
}
