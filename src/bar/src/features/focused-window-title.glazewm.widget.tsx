import { createMemo } from "solid-js";
import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";
import { showWindowPanel } from "./window-panel";

const MAX_DEPTH = 20;

export function FocusedWindowTitleGlazewmWidget() {
  const providers = useProviders();
  const isCurrentMonitor = createMemo(
    () =>
      providers.glazewm?.focusedMonitor.id ===
      providers.glazewm?.currentMonitor.id,
  );

  const title = createMemo(() => {
    let focusedWindow = providers.glazewm?.focusedWorkspace.children.find(
      (w) => w.hasFocus,
    );

    if (!focusedWindow) {
      return "Открытые окна";
    }

    let depth = 0;

    while (focusedWindow?.type !== "window" && depth < MAX_DEPTH) {
      focusedWindow = focusedWindow?.children.find((w) => w.hasFocus);
      depth++;
    }

    if (focusedWindow?.type === "window") {
      return focusedWindow.title;
    }

    return "Открытые окна";
  });

  return (
    <div class="window-panel-trigger h-full" onMouseEnter={() => showWindowPanel(providers.glazewm?.currentMonitor.id, true, providers.glazewm?.displayedWorkspace.name)} onMouseLeave={() => showWindowPanel(providers.glazewm?.currentMonitor.id, false)}>
    <GroupItem class="text-ellipsis whitespace-nowrap max-w-[200px] 2xl:max-w-[350px] lg:max-w-[200px]" onClick={() => showWindowPanel(providers.glazewm?.currentMonitor.id, true, providers.glazewm?.displayedWorkspace.name)}>
      <span
        title={title()}
        classList={{
          "text-rose-pine-muted hover:text-inherit": !isCurrentMonitor(),
        }}
      >
        {title()}
      </span>
    </GroupItem>
    </div>
  );
}
