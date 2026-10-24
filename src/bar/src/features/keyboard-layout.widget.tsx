import { GroupItem } from "@components/group.component";
import { useProviders } from "@providers/index";

export function KeyboardLayoutWidget() {
  const providers = useProviders();

  return <GroupItem>{providers.keyboard?.layout.split("-")[0]}</GroupItem>;
}
