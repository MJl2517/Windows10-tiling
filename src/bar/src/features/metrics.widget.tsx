import { useProviders } from "@providers/index";
import { GroupItem } from "@components/group.component";
import {
  animate,
  AnimationPlaybackControlsWithThen,
  MotionValue,
} from "motion";
import {
  Accessor,
  createEffect,
  createMemo,
  EffectFunction,
  ParentProps,
} from "solid-js";
import { useMotionValue } from "@/motion/hooks";
import { FaSolidMemory } from "solid-icons/fa";
import { FaSolidSun } from "solid-icons/fa";
import { RiDeviceCpuLine } from "solid-icons/ri";

function Metric(props: ParentProps) {
  return (
    <span class="flex items-center justify-center gap-1">{props.children}</span>
  );
}

function metricsAnimation(
  rawMotionValue: MotionValue<number>,
  metric: Accessor<number | undefined>,
): EffectFunction<
  AnimationPlaybackControlsWithThen | undefined,
  AnimationPlaybackControlsWithThen
> {
  return (prev) => {
    const control = animate(rawMotionValue, metric() || 0, {
      duration: 1,
      ease: "circOut",
      autoplay: Boolean(!prev || prev.state === "finished"),
    });

    if (prev && prev.state === "running") {
      prev?.then(() => {
        control.play();
      });
    }

    return control;
  };
}

export function MetricsWidget() {
  const providers = useProviders();
  const cpuUsage = useMotionValue(0);
  const memoryUsage = useMotionValue(0);
  const weather = useMotionValue(0);

  createEffect(
    metricsAnimation(
      cpuUsage.raw,
      createMemo(() => {
        const usage = providers.cpu?.usage;
        return usage;
      }),
    ),
  );

  createEffect(
    metricsAnimation(
      memoryUsage.raw,
      createMemo(() => {
        const usage = providers.memory?.usage;
        return usage;
      }),
    ),
  );

  createEffect(
    metricsAnimation(
      weather.raw,
      createMemo(() => {
        const usage = providers.weather?.celsiusTemp;
        return usage;
      }),
    ),
  );

  return (
    <GroupItem class="justify-end">
      <Metric>
        <RiDeviceCpuLine class="w-4 h-4 text-rose-pine-rose" />
        {Math.round(cpuUsage.get()).toLocaleString(undefined, {})}%
      </Metric>
      <Metric>
        <FaSolidMemory class="w-4 h-4 text-rose-pine-pine" />
        {Math.round(memoryUsage.get()).toLocaleString(undefined, {})}%
      </Metric>
      <Metric>
        <FaSolidSun
          class="w-3.5 h-3.5 transition-colors"
          classList={{
            "text-rose-pine-foam": weather.get() <= -20,

            "text-rose-pine-pine": weather.get() <= -10,

            "text-rose-pine-iris": weather.get() <= 5,

            "text-rose-pine-rose": weather.get() <= 14,

            "text-rose-pine-gold": weather.get() <= 25,

            "text-rose-pine-love": weather.get() >= 25,
          }}
        />
        {Math.round(weather.get())}°
      </Metric>
    </GroupItem>
  );
}
