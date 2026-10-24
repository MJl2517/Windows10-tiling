import { createMemo, Index, Show, Switch, Match } from "solid-js";
import { Motion, Presence } from "solid-motionone";
import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";
import { createStoredSignal } from "@/components/signal-storage.hook";
import { WorkspaceDisplayMode } from "@/components/workspaces.types";

export function WorkspacesGlazewmWidget() {
  const providers = useProviders();

  const displayModeStorageKey = createMemo(() => {
    const deviceId = providers.glazewm?.currentMonitor.deviceName;
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

  const focusWrokspace = async (workspaceId: string) => {
    await providers.glazewm?.runCommand(`focus --workspace ${workspaceId}`);
    await providers.glazewm?.runCommand('wm-redraw');
  };

  return (
    <GroupItem
      class="overflow-visible"
      onContextMenu={(e) => {
        e.preventDefault();
        toggleDisplayMode();
      }}
    >
      <Index each={providers.glazewm?.currentMonitor.children}>
        {(workspace) => (
          <Presence exitBeforeEnter>
            <Show
              when={workspace().children.length > 0 || workspace().isDisplayed || ["1", "2", "3", "4", "5", "6", "7"].includes(workspace().name)}
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
                    "text-rose-pine-gold font-bold": workspace().hasFocus,
                    "px-2":
                      displayMode() === WorkspaceDisplayMode.icons &&
                      !workspace().isDisplayed,
                  }}
                  onClick={() => {
                    focusWrokspace(workspace().name);
                  }}
                  animate={{
                    fontSize:
                      displayMode() === WorkspaceDisplayMode.icons &&
                      !workspace().isDisplayed
                        ? "1.5rem"
                        : "13px",
                  }}
                  exit={{
                    fontSize: 0,
                  }}
                >
                  <Switch>
                    <Match when={displayMode() === WorkspaceDisplayMode.normal}>
                      {workspace().displayName ?? workspace().name}
                    </Match>
                    <Match when={displayMode() === WorkspaceDisplayMode.icons}>
                      <Show
                        when={workspace().isDisplayed}
                        fallback={
                          (workspace().displayName ?? workspace().name)?.split(
                            " ",
                          )[0]
                        }
                      >
                        {(workspace().displayName ?? workspace().name)?.split(
                          " ",
                        )?.[1] ??
                          workspace().displayName ??
                          workspace().name}
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
