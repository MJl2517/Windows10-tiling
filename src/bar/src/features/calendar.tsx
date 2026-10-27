import { createMemo, createSignal, For, onCleanup, onMount } from "solid-js";
import { createProvider, currentWidget } from "zebar";
import { monthDays, sameDay } from "./calendar-month";

const calendarKey = "rose-pine:calendar:v1";
export function showCalendar(monitor: string | undefined) {
  if (monitor) localStorage.setItem(calendarKey, JSON.stringify({ monitor, at: Date.now() }));
}

export function Calendar(props: { preview?: boolean }) {
  const provider = props.preview ? undefined : createProvider({ type: "glazewm" });
  const [today, setToday] = createSignal(new Date());
  const [month, setMonth] = createSignal(new Date());
  const [selected, setSelected] = createSignal(new Date());
  const [visible, setVisible] = createSignal(!!props.preview);
  const days = createMemo(() => monthDays(month()));
  let monitor = "", lastRequest = 0, disposed = false;
  let nativeChange = Promise.resolve();
  let removeFocus: (() => void) | undefined;
  const setOpen = (open: boolean) => {
    setVisible(open);
    if (props.preview) return;
    nativeChange = nativeChange.then(async () => {
      if (disposed) return;
      const native = currentWidget().tauriWindow;
      if (open && visible()) { await native.show(); await native.setFocus(); }
      else if (!visible()) await native.hide();
    }).catch(console.error);
  };
  const reset = () => { const now = new Date(); setToday(now); setMonth(now); setSelected(now); };
  const shiftMonth = (delta: number) => setMonth(value => new Date(value.getFullYear(), value.getMonth() + delta, 1));
  const message = () => {
    if (!monitor) return;
    try {
      const request = JSON.parse(localStorage.getItem(calendarKey) ?? "null");
      if (!request || typeof request.at !== "number" || request.at <= lastRequest || Date.now() - request.at > 3000) return;
      lastRequest = request.at;
      if (request.monitor !== monitor) { setOpen(false); return; }
      reset(); setOpen(true);
    } catch { /* Ignore malformed or stale messages from other widget instances. */ }
  };
  const storage = (event: StorageEvent) => { if (event.key === calendarKey) message(); };
  const keyboard = (event: KeyboardEvent) => {
    if (!visible()) return;
    if (event.key === "Escape") { event.preventDefault(); setOpen(false); }
    else if (event.key === "PageUp" || event.key === "PageDown") { event.preventDefault(); shiftMonth(event.key === "PageUp" ? -1 : 1); }
  };
  onMount(() => {
    if (!props.preview) {
      setOpen(false);
      void currentWidget().tauriWindow.onFocusChanged(({ payload }) => { if (!payload && visible()) setOpen(false); }).then(remove => { if (disposed) remove(); else removeFocus = remove; });
      provider?.onOutput(output => { monitor = output.currentMonitor.id; message(); });
    }
    window.addEventListener("storage", storage);
    window.addEventListener("keydown", keyboard);
    const timer = setInterval(() => setToday(new Date()), 60000);
    onCleanup(() => { disposed = true; clearInterval(timer); provider?.stop(); removeFocus?.(); window.removeEventListener("storage", storage); window.removeEventListener("keydown", keyboard); });
  });
  return <section class="pine-calendar" classList={{ "pine-calendar-visible": visible() }} role="dialog" aria-label="Календарь" aria-hidden={!visible()}>
    <div class="pine-calendar-heading"><span>Календарь</span><button aria-label="Закрыть календарь" title="Закрыть · Esc" onClick={() => setOpen(false)}>×</button></div>
    <header><button aria-label="Предыдущий месяц" onClick={() => shiftMonth(-1)}>‹</button><h2 aria-live="polite">{month().toLocaleDateString("ru-RU", { month: "long", year: "numeric" })}</h2><button aria-label="Следующий месяц" onClick={() => shiftMonth(1)}>›</button></header>
    <div class="pine-calendar-grid" aria-label="Дни месяца">
      <For each={["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]}>{day => <span class="pine-calendar-weekday">{day}</span>}</For>
      <For each={days()}>{day => <button classList={{ "pine-calendar-outside": day.getMonth() !== month().getMonth(), "pine-calendar-today": sameDay(day, today()), "pine-calendar-selected": sameDay(day, selected()), "pine-calendar-weekend": day.getDay() === 0 || day.getDay() === 6 }} aria-label={day.toLocaleDateString("ru-RU", { day: "numeric", month: "long", year: "numeric" })} aria-current={sameDay(day, today()) ? "date" : undefined} aria-pressed={sameDay(day, selected())} onClick={() => { setSelected(day); if (day.getMonth() !== month().getMonth()) setMonth(new Date(day.getFullYear(), day.getMonth(), 1)); }}>{day.getDate()}</button>}</For>
    </div>
    <footer><span>{selected().toLocaleDateString("ru-RU", { day: "numeric", month: "long", weekday: "short" })}</span><button onClick={reset}>Сегодня</button></footer>
  </section>;
}
