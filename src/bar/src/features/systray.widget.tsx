import { createEffect, createMemo, createResource, createSignal, For, onCleanup, onMount, Show } from "solid-js";
import { shellExec, type SystrayOutput } from "zebar";
import { createStoredSignal } from "@/components/signal-storage.hook";
import { stableTrayKey } from "./tray-identity";

const storageKey = "rose-pine:hidden-tray-icons:v1";
const orderKey = "rose-pine:tray-icon-order:v1";

export function SystrayWidget(props: { tray?: SystrayOutput | null }) {
  const [hidden, setHidden] = createStoredSignal<string[]>([], () => storageKey);
  const [order, setOrder] = createStoredSignal<string[]>([], () => orderKey);
  const [identities, { refetch }] = createResource(
    () => (props.tray?.icons ?? []).map(icon => icon.id).filter(id => /^\d+:\d+$/.test(id)).sort().join(" "),
    async (ids, previous): Promise<Record<string, string | null>> => {
      if (!ids) return {};
      const fallback = (id: string) => {
        const icon = props.tray?.icons.find(item => item.id === id);
        // ponytail: inaccessible/vanished processes use their label; use provider processPath when available.
        return `tip:${icon?.tooltip.split("\n")[0]?.trim().toLowerCase() || icon?.iconHash}|${id.split(":")[1]}`;
      };
      let resolved: Record<string, string | null> = {};
      try {
        const result = await shellExec("@PROFILE_F@/.glzr/zebar/bar-rose-pine/tools/tray-identity.exe", ids.split(" "));
        if (result.code !== 0) throw new Error("Tray identity lookup failed");
        const value: unknown = JSON.parse(result.stdout);
        if (!value || typeof value !== "object" || Array.isArray(value) || !Object.values(value).every(key => key === null || (typeof key === "string" && key.startsWith("exe:")))) throw new Error("Invalid tray identities");
        resolved = value as Record<string, string | null>;
      } catch (error) {
        console.warn(error);
        resolved = previous.value ?? {};
      }
      const lookup: Record<string, string | null> = {};
      for (const id of ids.split(" ")) {
        const key = resolved[id];
        const label = fallback(id);
        lookup[id] = key === undefined ? label : key;
        if (key?.startsWith("exe:")) lookup[label] = key;
      }
      return lookup;
    },
  );
  const identity = (id: string) => stableTrayKey(identities()?.[id] ?? id);
  // Convert saved selections from the previous format while their old handles still exist.
  createEffect(() => {
    if (!identities() || identities.loading) return;
    for (const [values, setValues] of [[hidden, setHidden], [order, setOrder]] as const) {
      const migrated = [...new Set(values().map(identity))];
      if (JSON.stringify(migrated) !== JSON.stringify(values())) setValues(migrated);
    }
  });
  const [editing, setEditing] = createSignal(false);
  const [expanded, setExpanded] = createSignal(false);
  const [dragging, setDragging] = createSignal<string | null>(null);
  const [dropTarget, setDropTarget] = createSignal<string | null>(null);
  let pointerStart: { id: string; x: number; y: number } | null = null;
  let suppressClick = false;
  const isHidden = (id: string) => hidden().includes(identity(id));
  // ponytail: GUID icons carry no callback handle here; Zebar must expire those itself.
  const liveIcons = createMemo(() => (props.tray?.icons ?? []).filter(icon => identities.latest?.[icon.id] !== null));
  const hiddenCount = createMemo(() => liveIcons().filter(icon => isHidden(icon.id)).length);
  const orderedIcons = createMemo(() => {
    const ranks = new Map(order().map((id, index) => [id, index]));
    return [...liveIcons()].sort((a, b) => (ranks.get(identity(a.id)) ?? ranks.size) - (ranks.get(identity(b.id)) ?? ranks.size));
  });
  const visibleIcons = createMemo(() => orderedIcons().filter(icon => editing() || expanded() || !isHidden(icon.id)));
  const reorder = (source: string, target: string) => {
    if (source === target || !orderedIcons().some(icon => icon.id === source) || !orderedIcons().some(icon => icon.id === target)) return;
    const ids = [...new Set([...order(), ...orderedIcons().map(icon => identity(icon.id))])];
    const targetIndex = ids.indexOf(identity(target));
    ids.splice(ids.indexOf(identity(source)), 1);
    ids.splice(targetIndex, 0, identity(source));
    setOrder(ids);
  };
  const toggle = (id: string) => { const key = identity(id); setHidden(ids => ids.includes(key) ? ids.filter(item => item !== key) : [...ids, key]); };
  const action = (handler: ((id: string) => Promise<void>) | undefined, id: string) => {
    if (!editing()) void handler?.(id).catch(console.warn);
  };
  const sync = (event: StorageEvent) => {
    if (event.key !== storageKey && event.key !== orderKey) return;
    try {
      const value: unknown = JSON.parse(event.newValue ?? "[]");
      if (Array.isArray(value) && value.every(item => typeof item === "string")) {
        if (event.key === orderKey) setOrder(value); else setHidden(value);
      }
    } catch { /* Keep the last valid selection. */ }
  };
  const escape = (event: KeyboardEvent) => {
    if (event.key === "Escape") { setEditing(false); setExpanded(false); setDragging(null); setDropTarget(null); pointerStart = null; }
  };
  onMount(() => {
    // Zebar may emit no event when an app exits without unregistering its icon.
    const timer = window.setInterval(() => { if (!identities.loading) void refetch(); }, 5000);
    onCleanup(() => window.clearInterval(timer));
    window.addEventListener("storage", sync);
    window.addEventListener("keydown", escape);
  });
  onCleanup(() => {
    window.removeEventListener("storage", sync);
    window.removeEventListener("keydown", escape);
  });

  return (
    <div class="tray" role="group" aria-label="Системный трей">
      <Show when={hiddenCount() > 0 && !editing()}>
        <button class="tray-control" aria-label="Показать скрытые значки" aria-expanded={expanded()}
          title={expanded() ? "Свернуть скрытые значки" : `Скрытые значки: ${hiddenCount()}`}
          onClick={() => setExpanded(value => !value)}>{expanded() ? "›" : "‹"}</button>
      </Show>
      <div class="tray-icons" classList={{ "tray-editing": editing() }}
        onWheel={event => { if (event.deltaY) { event.preventDefault(); event.currentTarget.scrollLeft += event.deltaY; } }}>
        <For each={visibleIcons()}>{icon => (
          <button class="tray-icon" data-tray-id={icon.id}
            classList={{ "tray-icon-hidden": isHidden(icon.id), "tray-draggable": editing(), "tray-dragging": dragging() === icon.id, "tray-drop-target": dropTarget() === icon.id && dragging() !== icon.id }}
            aria-label={editing() ? `${isHidden(icon.id) ? "Показать" : "Скрыть"}: ${icon.tooltip || "Приложение"}` : icon.tooltip || "Приложение"}
            aria-pressed={editing() ? !isHidden(icon.id) : undefined}
            title={editing() ? `${isHidden(icon.id) ? "Показать" : "Скрыть"}: ${icon.tooltip || "Приложение"}` : icon.tooltip}
            onPointerDown={event => {
              if (!editing() || event.button !== 0) return;
              pointerStart = { id: icon.id, x: event.clientX, y: event.clientY };
              event.currentTarget.setPointerCapture(event.pointerId);
            }}
            onPointerMove={event => {
              if (!pointerStart || !editing()) return;
              if (!dragging() && Math.hypot(event.clientX - pointerStart.x, event.clientY - pointerStart.y) < 5) return;
              setDragging(pointerStart.id);
              setDropTarget(document.elementFromPoint(event.clientX, event.clientY)?.closest<HTMLElement>("[data-tray-id]")?.dataset.trayId ?? null);
            }}
            onPointerUp={() => {
              if (dragging()) {
                const target = dropTarget();
                if (target) reorder(dragging()!, target);
                suppressClick = true;
                setTimeout(() => { suppressClick = false; }, 0);
              }
              pointerStart = null; setDragging(null); setDropTarget(null);
            }}
            onPointerCancel={() => { pointerStart = null; setDragging(null); setDropTarget(null); }}
            onKeyDown={event => {
              if (!editing() || !event.shiftKey || !["ArrowLeft", "ArrowRight"].includes(event.key)) return;
              event.preventDefault();
              const icons = orderedIcons();
              const target = icons[icons.findIndex(item => item.id === icon.id) + (event.key === "ArrowRight" ? 1 : -1)];
              if (target) reorder(icon.id, target.id);
            }}
            onClick={event => {
              if (suppressClick) { suppressClick = false; return; }
              if (editing()) toggle(icon.id);
              else if (event.detail < 2) action(props.tray?.onLeftClick, icon.id);
            }}
            onDblClick={() => action(props.tray?.onLeftDoubleClick, icon.id)}
            onContextMenu={event => { event.preventDefault(); action(props.tray?.onRightClick, icon.id); }}
            onAuxClick={event => { if (event.button === 1) action(props.tray?.onMiddleClick, icon.id); }}
            onMouseEnter={() => action(props.tray?.onHoverEnter, icon.id)}
            onMouseLeave={() => action(props.tray?.onHoverLeave, icon.id)}>
            <img src={icon.iconUrl} alt="" draggable={false} />
            <Show when={editing()}><span class="tray-mark">{isHidden(icon.id) ? "−" : "✓"}</span></Show>
          </button>
        )}</For>
      </div>
      <button class="tray-control" classList={{ "tray-control-active": editing() }}
        aria-label={editing() ? "Готово" : "Настроить значки трея"} aria-pressed={editing()}
        title={editing() ? "Перетаскивай значки для изменения порядка. Клик — скрыть/вернуть; Shift+←/→ — переставить. Готово — ✓ или Esc." : "Настроить значки трея"}
        onClick={() => { setEditing(value => !value); setExpanded(false); }}>{editing() ? "✓" : "⚙"}</button>
    </div>
  );
}
