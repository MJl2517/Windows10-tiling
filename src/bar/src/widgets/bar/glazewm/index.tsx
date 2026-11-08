/* @refresh reload */
import "@/index.css";
import { render } from "solid-js/web";
import { motion } from "solid-motionone";
import { ProvidersProvider, useProviders } from "@providers/index";
import { Group } from "@components/group.component";
import { MediaWidget } from "@features/media.widget";
import { MetricsWidget } from "@features/metrics.widget";
import { KeyboardLayoutWidget } from "@features/keyboard-layout.widget";
import { DateTimeWidget } from "@features/date-time.widget";
import { SystrayWidget } from "@features/systray.widget";
import { onMount } from "solid-js";
import { shellExec } from "zebar";
import { WorkspacesGlazewmWidget } from "@/features/workspaces.glazewm.widget";
import { FocusedWindowTitleGlazewmWidget } from "@/features/focused-window-title.glazewm.widget";
motion;

render(() => <App />, document.getElementById("root")!);

export function LeftGroup() {
  return (
    <Group
      animationOptions={{
        initial: {
          x: "-200%",
        },
        animate: {
          x: 0,
        },
        transition: {
          duration: 2.0,
        },
      }}
      class="justify-self-start justify-start"
    >
      <WorkspacesGlazewmWidget />
      <MediaWidget />
    </Group>
  );
}

export function CenterGroup() {
  return (
    <Group
      animationOptions={{
        initial: {
          y: "-200%",
        },
        animate: {
          y: 0,
        },
        transition: {
          duration: 2.0,
        },
      }}
      class="justify-self-center"
    >
      <FocusedWindowTitleGlazewmWidget />
    </Group>
  );
}

export function RightGroup() {
  const providers = useProviders();
  return (
    <Group
      animationOptions={{
        initial: {
          x: "200%",
        },
        animate: {
          x: 0,
        },
        transition: {
          duration: 2.0,
        },
      }}
      class="justify-self-end justify-end"
    >
      <MetricsWidget />
      <KeyboardLayoutWidget />
      <div class="inline-flex min-w-0 items-center gap-1">
        <SystrayWidget tray={providers.tray} />
        <button class="tray-control" title="Центр управления Rose Pine Desktop" aria-label="Центр управления" style={{ color: "var(--color-rose-pine-iris)" }} onClick={() => void shellExec("@ROOT_F@/RosePineCenter.exe", [])}>◆</button>
      </div>
      <DateTimeWidget />
    </Group>
  );
}

function App() {
  onMount(() => {
    setTimeout(() => {
      for (let i = 0; i < document.styleSheets.length; i++) {
        if (document.styleSheets[i]?.href?.includes("/__zebar/normalize.css")) {
          document.styleSheets[i]!.disabled = true;
        }
      }
    }, 2000);
  });
  return (
    <ProvidersProvider WmType="glazewm">
      <div class="h-full grid grid-cols-3 px-[16px] items-end">
        <LeftGroup />
        <CenterGroup />
        <RightGroup />
      </div>
    </ProvidersProvider>
  );
}
