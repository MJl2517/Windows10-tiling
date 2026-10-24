import { createEffect, createMemo, createSignal, For, on, onCleanup, onMount, Show } from "solid-js";
import { createProvider, currentWidget, shellExec, type GlazeWmOutput } from "zebar";
import { LogicalSize } from "@tauri-apps/api/dpi";
import { createStore, reconcile } from "solid-js/store";

export const panelKey = "rose-pine:window-panel:v1";
export function showWindowPanel(monitor: string | undefined, open: boolean, workspace?: string) {
  if (monitor) localStorage.setItem(panelKey, JSON.stringify({ monitor, open, workspace, at: Date.now() }));
}
type Task = { handle: number; title: string; processName: string; icon: string; active: boolean; minimized: boolean };
const helper = "@PROFILE_F@/.glzr/zebar/bar-rose-pine/tools/task-windows.exe";

export function WindowPanel(props: { preview?: boolean; wm?: GlazeWmOutput; tasks?: Task[]; record?: (command: string) => void }) {
  const provider = props.preview ? undefined : createProvider({ type: "glazewm" });
  const [output, setOutput] = createSignal<GlazeWmOutput>();
  const wm = () => props.wm ?? output();
  const [native, setNative] = createSignal<Task[]>([]);
  const [error, setError] = createSignal("");
  const [visible, setVisible] = createSignal(!!props.preview);
  const [menu, setMenu] = createSignal<{ task: Task; x: number; y: number }>();
  const [dragging, setDragging] = createSignal<number>();
  let destinationWorkspace: string | undefined;
  let drag: { task: Task; x: number; y: number; moved: boolean; workspace?: string } | undefined;
  let suppressClick = false;
  const taskValues = createMemo(() => {
    const rows = new Map((props.tasks ?? native()).map(task => [task.handle, { ...task }]));
    for (const win of wm()?.allWindows ?? []) {
      const row = rows.get(win.handle);
      rows.set(win.handle, { handle: win.handle, title: win.title, processName: win.processName, icon: row?.icon ?? "", active: win.hasFocus, minimized: win.state.type === "minimized" });
    }
    return [...rows.values()].sort((a, b) => a.processName.localeCompare(b.processName) || a.handle - b.handle);
  });
  const [taskRows, setTaskRows] = createStore<Task[]>([]);
  createEffect(() => setTaskRows(reconcile(taskValues(), { key: "handle" })));
  const tasks = () => taskRows;
  const findWorkspace = (handle: number) => {
    const contains = (items: { type: string; handle?: number; children?: unknown[] }[]): boolean => items.some(item => item.handle === handle || (item.children ? contains(item.children as typeof items) : false));
    return wm()?.allWorkspaces.find(ws => contains(ws.children));
  };
  const workspace = (handle: number) => findWorkspace(handle)?.displayName ?? "";
  let closeTimer: ReturnType<typeof setTimeout> | undefined;
  let pollTimer: ReturnType<typeof setTimeout> | undefined;
  let busy = false, disposed = false;
  let visibilityChange = Promise.resolve();
  const setNativeVisible = (open: boolean) => {
    if (props.preview) return Promise.resolve();
    visibilityChange = visibilityChange.then(() => open ? currentWidget().tauriWindow.show() : currentWidget().tauriWindow.hide()).catch(failure => { setError(String(failure)); });
    return visibilityChange;
  };
  const stopClosing = () => clearTimeout(closeTimer);
  const hide = async () => { stopClosing(); setMenu(undefined); setVisible(false); await setNativeVisible(false); };
  const leave = () => { stopClosing(); if (!drag) closeTimer = setTimeout(() => void hide(), 240); };
  const refresh = async () => {
    if (busy || disposed || props.preview || !visible()) return;
    busy = true;
    try {
      const result = await shellExec(helper, ["--list", ...(wm()?.allWindows ?? []).map(win => String(win.handle))]);
      if (result.code !== 0) throw new Error(result.stderr || "Не удалось прочитать окна");
      const rows: unknown = JSON.parse(result.stdout);
      if (!Array.isArray(rows) || !rows.every(row => Number.isSafeInteger(row.handle) && row.handle > 0 && typeof row.title === "string" && typeof row.processName === "string" && typeof row.icon === "string" && row.icon.startsWith("data:image/png;base64,"))) throw new Error("Некорректный список окон");
      if (!disposed) { setNative(rows as Task[]); setError(""); }
    } catch (failure) { if (!disposed) setError(String(failure)); }
    finally { busy = false; }
  };
  const select = async (task: Task) => {
    try {
      const win = wm()?.allWindows.find(win => win.handle === task.handle);
      if (win) {
        // Cached hasFocus can refer to the last window on an inactive workspace.
        // Clicking a task always opens it; minimizing belongs in the context menu.
        if (win.state.type === "minimized") await wm()!.runCommand("toggle-minimized", win.id);
        const target = findWorkspace(task.handle);
        if (target) await wm()!.runCommand(`focus --workspace ${target.name}`);
        await wm()!.runCommand(`focus --container-id ${win.id}`);
        await wm()!.runCommand("wm-redraw");
      } else if (props.preview) props.record?.(`activate:${task.handle}`);
      else {
        const result = await shellExec(helper, ["--activate", String(task.handle)]);
        if (result.code !== 0) throw new Error(result.stderr || "Окно уже закрыто или недоступно");
      }
      await hide();
    } catch (failure) { setError(String(failure)); }
  };
  const moveHere = async (task: Task, destination = destinationWorkspace ?? wm()?.displayedWorkspace?.name) => {
    try {
      const win = wm()?.allWindows.find(win => win.handle === task.handle);
      if (!win || !destination) throw new Error("Это окно не управляется GlazeWM");
      if (win.state.type === "minimized") await wm()!.runCommand("toggle-minimized", win.id);
      await wm()!.runCommand(`move --workspace ${destination}`, win.id);
      await wm()!.runCommand(`focus --workspace ${destination}`);
      await wm()!.runCommand(`focus --container-id ${win.id}`);
      await wm()!.runCommand("wm-redraw"); await hide();
    } catch (failure) { setError(String(failure)); }
  };
  const action = async (task: Task, command: "close" | "minimize") => {
    try {
      const win = wm()?.allWindows.find(win => win.handle === task.handle);
      if (props.preview && command === "close") props.record?.(`close:${task.handle}`);
      else if (command === "close") {
        const result = await shellExec("@PROFILE_F@/.glzr/tools/close-window/close-window.exe", ["--handle", String(task.handle)]);
        if (result.code !== 0) throw new Error("Не удалось закрыть окно");
      } else if (win) await wm()!.runCommand("set-minimized", win.id);
      else if (props.preview) props.record?.(`minimize:${task.handle}`);
      else { const result = await shellExec(helper, ["--minimize", String(task.handle)]); if (result.code !== 0) throw new Error("Не удалось свернуть окно"); }
      await hide();
    } catch (failure) { setError(String(failure)); }
  };
  const message = (event?: StorageEvent) => {
    if (event && event.key !== panelKey) return;
    try {
      const value = JSON.parse(localStorage.getItem(panelKey) ?? "null");
      if (!value || Date.now() - value.at > 2000) return;
      if (value.monitor !== wm()?.currentMonitor.id) { void hide(); return; }
      if (value.open) {
        destinationWorkspace = value.workspace ?? wm()?.displayedWorkspace?.name;
        stopClosing(); setVisible(true);
        void setNativeVisible(true);
        void refresh();
      } else leave();
    } catch (failure) { console.warn(failure); }
  };
  onMount(() => {
    if (!props.preview) { void setNativeVisible(false); provider!.onOutput(setOutput); }
    window.addEventListener("storage", message);
    const poll = () => { void refresh(); pollTimer = setTimeout(poll, 1500); }; poll();
  });
  createEffect(on(() => wm()?.currentMonitor.id, id => { if (id) message(); }));
  createEffect(() => {
    // Header, padding and outer margins need 72px in addition to the card rows.
    const height = Math.max(menu() ? 220 : 0, Math.min(320, 72 + Math.ceil(Math.max(1, tasks().length) / 2) * 72 + (error() ? 28 : 0)));
    if (!props.preview) void currentWidget().tauriWindow.setSize(new LogicalSize(700, height)).catch(failure => console.warn(failure));
  });
  onCleanup(() => { disposed = true; stopClosing(); clearTimeout(pollTimer); provider?.stop(); window.removeEventListener("storage", message); });
  return <section class="window-panel" classList={{ "window-panel-visible": visible() }} onMouseEnter={stopClosing} onMouseLeave={leave} onPointerDown={() => setMenu(undefined)} onKeyDown={event => { if (event.key === "Escape") { if (menu()) setMenu(undefined); else { drag = undefined; setDragging(undefined); void hide(); } } }} aria-label="Открытые окна">
    <header><span>Открытые окна</span><span class="window-panel-hint">ПКМ — действия · перетащить из панели — на этот стол</span></header>
    <div class="window-panel-list">
      <For each={tasks()}>{task => <button class="window-task" classList={{ "window-task-active": task.active, "window-task-minimized": task.minimized, "window-task-dragging": dragging() === task.handle }} title={task.title + (workspace(task.handle) ? ` · ${workspace(task.handle)}` : "")} aria-label={task.title} aria-pressed={task.active} data-handle={task.handle}
        onClick={() => { if (suppressClick) { suppressClick = false; return; } void select(task); }}
        onContextMenu={event => { event.preventDefault(); stopClosing(); setMenu({ task, x: Math.max(8, Math.min(event.clientX, window.innerWidth - 202)), y: Math.max(8, Math.min(event.clientY, window.innerHeight - 166)) }); }}
        onPointerDown={event => { if (event.button !== 0 || !wm()?.allWindows.some(win => win.handle === task.handle)) return; suppressClick = false; drag = { task, x: event.screenX, y: event.screenY, moved: false, workspace: destinationWorkspace ?? wm()?.displayedWorkspace?.name }; event.currentTarget.setPointerCapture(event.pointerId); stopClosing(); }}
        onPointerMove={event => { if (drag?.task.handle === task.handle && Math.hypot(event.screenX - drag.x, event.screenY - drag.y) > 8) { drag.moved = true; setDragging(task.handle); } }}
        onPointerUp={event => { if (!drag || drag.task.handle !== task.handle) return; const state = drag; drag = undefined; setDragging(undefined); event.currentTarget.releasePointerCapture(event.pointerId); if (state.moved) { suppressClick = true; if (event.clientX < 4 || event.clientX > window.innerWidth - 4 || event.clientY < 4 || event.clientY > window.innerHeight - 4) void moveHere(task, state.workspace); } }}
        onPointerCancel={() => { drag = undefined; setDragging(undefined); suppressClick = true; }}>
        <Show when={task.icon} fallback={<span class="window-task-fallback">{task.processName.charAt(0).toUpperCase() || "□"}</span>}><img src={task.icon} alt="" /></Show>
        <span class="window-task-text"><strong>{task.processName || task.title}</strong><span>{task.title}</span></span>
        <span class="window-task-workspace">{workspace(task.handle) || (task.minimized ? "Свёрнуто" : "")}</span>
      </button>}</For>
      <Show when={tasks().length === 0}><p class="window-panel-empty">Нет открытых окон</p></Show>
    </div>
    <Show when={error()}><p class="window-panel-error" role="alert">{error()}</p></Show>
    <Show when={menu()}>{entry => <div class="window-task-menu" role="menu" style={{ left: `${entry().x}px`, top: `${entry().y}px` }} onPointerDown={event => event.stopPropagation()}>
      <button role="menuitem" onClick={() => void select(entry().task)}>Открыть окно</button>
      <button role="menuitem" onClick={() => void moveHere(entry().task)} disabled={!wm()?.allWindows.some(win => win.handle === entry().task.handle)}>Перенести на этот стол</button>
      <button role="menuitem" onClick={() => void action(entry().task, "minimize")}>Свернуть</button>
      <button role="menuitem" class="window-task-close" onClick={() => void action(entry().task, "close")}>Закрыть окно</button>
    </div>}</Show>
  </section>;
}
