import "@/index.css";
import { render } from "solid-js/web";
import { Calendar } from "@/features/calendar";
render(() => <Calendar preview={new URLSearchParams(location.search).has("preview")} />, document.getElementById("root")!);
