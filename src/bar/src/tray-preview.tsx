import "./index.css";
import { render } from "solid-js/web";
import type { SystrayOutput } from "zebar";
import { SystrayWidget } from "./features/systray.widget";

const calls: string[] = [];
const params = new URLSearchParams(location.search);
const handles = params.has("handles");
const session = Number(params.get("session") ?? 1);
if (handles) {
  (window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = {
    invoke: async (command: string, args: { args: string[] }) => {
      if (command !== "shell_exec") throw new Error("Unexpected command " + command);
      return { code: 0, stdout: JSON.stringify(Object.fromEntries(args.args.map(id => {
        const uid = Number(id.split(":")[1]);
        return [id, `exe:c:\\apps\\${["Discord", "Steam", "VPN"][uid - 1]}.exe|${uid}`];
      }))), stderr: "" };
    },
  };
}
(window as unknown as { trayCalls: string[] }).trayCalls = calls;
const record = (name: string) => async (id: string) => { calls.push(name + ":" + id); };
const tray: SystrayOutput = {
  icons: ["Discord", "Steam", "VPN"].map((name, index) => ({
    id: handles ? `${session * 100 + index + 1}:${index + 1}` : name,
    tooltip: handles && session > 1 ? `${name} — новая подсказка` : name,
    iconBytes: [], iconBlob: new Blob(), iconHash: handles ? `${name}-${session}` : name,
    iconUrl: "data:image/svg+xml," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" rx="7" fill="${["#c4a7e7", "#9ccfd8", "#f6c177"][index]}"/><text x="16" y="23" text-anchor="middle" font-family="sans-serif" font-size="22" fill="#191724">${name[0]}</text></svg>`),
  })),
  onLeftClick: record("left"), onLeftDoubleClick: record("double"), onRightClick: record("right"),
  onMiddleClick: record("middle"), onHoverEnter: record("enter"), onHoverLeave: record("leave"), onHoverMove: record("move"),
};
document.body.style.cssText = "padding:8px;background:#191724";
render(() => <div style="height:32px;display:flex;justify-content:flex-end;align-items:center;gap:12px;padding:0 18px;background:#26233a;color:#e0def4;border:2px solid #6e6a86;border-radius:24px">
  <span>CPU 12% · RAM 34%</span><span>RU</span><SystrayWidget tray={tray} /><span>21:15</span>
</div>, document.getElementById("root")!);
