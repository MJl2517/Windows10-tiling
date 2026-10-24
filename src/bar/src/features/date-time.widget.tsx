import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";

export function DateTimeWidget() {
  const providers = useProviders();

  return <GroupItem>{providers.date?.formatted}</GroupItem>;
}
