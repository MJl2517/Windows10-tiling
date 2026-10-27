import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";
import { showCalendar } from "./calendar";

export function DateTimeWidget() {
  const providers = useProviders();

  return <GroupItem><button class="pine-calendar-trigger" aria-label="Открыть календарь" aria-haspopup="dialog" title="Открыть календарь" onClick={() => showCalendar(providers.glazewm?.currentMonitor.id)}>{providers.date?.formatted}</button></GroupItem>;
}
