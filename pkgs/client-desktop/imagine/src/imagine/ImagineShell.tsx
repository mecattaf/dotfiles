// Imagine owns this shell; native components derive from pinned Manganese.
// Extracted fork baseline: 67c29a9906905bd5e1679803232c2f510b3fed9e, MIT (LICENSE).
import { applyAppearance } from "@domicile-desktop/component-library/appearance";
import { DisplayProvider } from "@domicile-desktop/component-library/DisplayProvider";
import { Provider } from "@domicile-desktop/component-library/Provider";
import { applyTheme, DEFAULT_THEME } from "@domicile-desktop/component-library/theme-core";
import type { ImagineOptions } from "./ImagineOptions";
import { applicationsConfigSchema } from "@domicile-desktop/manganese-launcher/applications-config";
import { floatingRulesSchema } from "@domicile-desktop/manganese-window-management/floating/floating-rules";
import { DEFAULT_KEYBINDINGS } from "@domicile-desktop/manganese-window-management/keyboard/commands";
import { hostDisplays } from "@domicile-desktop/manganese-window-management/screens/host-displays";
import { useAppearance } from "@domicile-desktop/react/appearance";
import { useDomicile } from "@domicile-desktop/react/domicile-provider";
import { mount } from "@domicile-desktop/react/mount";
import type { Shell } from "@domicile-desktop/sdk/shell";
import { useLayoutEffect, useMemo } from "react";
import { Desktop } from "./Desktop";
import { hostTheme, rememberedTheme } from "./theme";
import { ambientChatConfig } from "./AmbientChat";
import { chatWindowConfig } from "./ChatWindow";
import { catalogueConfig } from "./SessionCatalogue";

// Imagine owns the Settings declaration copied from the pinned baseline.
export { options } from "./options";
export type { ImagineOptions } from "./ImagineOptions";

/** Mount Imagine's own desktop and policy using public native components. */
export const runImagine = (options: ImagineOptions = {}): Shell => {
  const applications = applicationsConfigSchema.parse(options.applications);
  const floating = floatingRulesSchema.parse(options.floating);
  const ambientChat = ambientChatConfig(options.ambientChat);
  const chatWindow = chatWindowConfig(options.chatWindow);
  const sessionCatalogue = catalogueConfig(options.sessionCatalogue);
  const App = () => {
    const domicile = useDomicile();
    const appearance = useAppearance();
    const theme = useMemo(() => hostTheme(domicile), [domicile]);
    const displays = useMemo(() => hostDisplays(domicile), [domicile]);
    useLayoutEffect(() => applyAppearance(appearance), [appearance]);
    return <Provider theme={theme}>
      <DisplayProvider source={displays}>
        <Desktop applications={applications} floating={floating}
          keybindings={options.keybindings ?? { keybindings: DEFAULT_KEYBINDINGS }}
          policy={options.policy} ambientChat={ambientChat} chatWindow={chatWindow} webBrowser={options.webBrowser} sessionCatalogue={sessionCatalogue} layoutPersistence={options.layoutPersistence} displayTemperature={options.displayTemperature} />
      </DisplayProvider>
    </Provider>;
  };
  return (root, domicile) => {
    applyTheme(rememberedTheme() ?? DEFAULT_THEME);
    mount(App)(root, domicile);
  };
};
