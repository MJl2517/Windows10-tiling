import { createMemo, Index, Show, Switch, Match } from "solid-js";
import { Motion, Presence } from "solid-motionone";
import { GroupItem } from "@components/group.component";
import { shellExec } from "zebar";
import { useProviders } from "@providers/index";
import { createStoredSignal } from "@/components/signal-storage.hook";
import { WorkspaceDisplayMode } from "@/components/workspaces.types";

export function WorkspacesKomorebiWidget() {
  const providers = useProviders();

  const displayModeStorageKey = createMemo(() => {
    const deviceId = providers.komorebi?.currentMonitor.deviceId;
    if (!deviceId) {
      return undefined;
    }

    return `${deviceId}:workspaces-display-mode`;
  });

  const [displayMode, setDisplayMode] = createStoredSignal(
    WorkspaceDisplayMode.normal,
    displayModeStorageKey,
  );

  const toggleDisplayMode = () => {
    setDisplayMode(
      displayMode() === WorkspaceDisplayMode.normal
        ? WorkspaceDisplayMode.icons
        : WorkspaceDisplayMode.normal,
    );
  };

  const focusWrokspace = async (monitorIndex: number, index: number) => {
    await shellExec("komorebic", [
      "focus-monitor-workspace",
      monitorIndex.toString(),
      index.toString(),
    ]);
  };

  const currentMonitorWorkspace = createMemo(() => {
    return providers.komorebi?.currentMonitor.workspaces[
      providers.komorebi?.currentMonitor.focusedWorkspaceIndex
    ];
  });

  return (
    <GroupItem
      class="overflow-visible"
      onContextMenu={(e) => {
        e.preventDefault();
        toggleDisplayMode();
      }}
    >
      <Index each={providers.komorebi?.currentMonitor.workspaces}>
        {(workspace) => (
          <Presence exitBeforeEnter>
            <Show
              when={
                workspace().tilingContainers.length > 0 ||
                workspace().floatingWindows.length > 0 ||
                workspace().maximizedWindow ||
                workspace().monocleContainer ||
                workspace() === currentMonitorWorkspace()
              }
            >
              <Motion.span
                class="origin-left inline-flex items-center justify-center h-full w-full py-1"
                initial={{
                  scale: 0,
                }}
                animate={{
                  scale: 1,
                }}
                exit={{
                  scale: 0.5,
                }}
              >
                <Motion.button
                  class="origin-left transition-colors h-[90%] rounded-[0.25rem] overflow-hidden hover:scale-105 hover:border-rose-pine-gold border-solid border-t-1 border-transparent inline-flex items-center justify-center"
                  classList={{
                    "text-rose-pine-gold font-bold":
                      workspace() === currentMonitorWorkspace(),
                    "px-2":
                      displayMode() === WorkspaceDisplayMode.icons &&
                      workspace() !==
                        providers.komorebi?.currentMonitor.workspaces[
                          providers.komorebi?.currentMonitor
                            .focusedWorkspaceIndex
                        ],
                  }}
                  onClick={() =>
                    focusWrokspace(
                      providers.komorebi?.allMonitors.indexOf(
                        providers.komorebi?.currentMonitor,
                      ) ?? 0,
                      providers.komorebi?.currentMonitor.workspaces.indexOf(
                        workspace(),
                      ) ?? 0,
                    )
                  }
                  animate={{
                    fontSize:
                      displayMode() === WorkspaceDisplayMode.icons &&
                      workspace() !==
                        providers.komorebi?.currentMonitor.workspaces[
                          providers.komorebi?.currentMonitor
                            .focusedWorkspaceIndex
                        ]
                        ? "1.5rem"
                        : "13px",
                  }}
                  exit={{
                    fontSize: 0,
                  }}
                >
                  <Switch>
                    <Match when={displayMode() === WorkspaceDisplayMode.normal}>
                      {workspace().name}
                    </Match>
                    <Match when={displayMode() === WorkspaceDisplayMode.icons}>
                      <Show
                        when={workspace() === currentMonitorWorkspace()}
                        fallback={workspace().name?.split(" ")[0]}
                      >
                        {workspace().name?.split(" ")?.[1] ?? workspace().name}
                      </Show>
                    </Match>
                  </Switch>
                </Motion.button>
              </Motion.span>
            </Show>
          </Presence>
        )}
      </Index>
    </GroupItem>
  );
}
