// Options extracted from the Manganese entry at 67c29a9906905bd5e1679803232c2f510b3fed9e.
// MIT (LICENSE). Imagine deliberately omits bars, wallpapers and inbox wiring.
import type { ApplicationsOptions } from "@domicile-desktop/manganese-launcher/applications-config";
import type { FloatingOptions } from "@domicile-desktop/manganese-window-management/floating/floating-rules";
import type { ShellKeybindings } from "@domicile-desktop/sdk/own-keybindings";
import type { AgencyPolicy } from "./policy";
import type { AmbientChatOptions } from "./AmbientChat";
import type { ChatWindowOptions } from "./ChatWindow";
import type { WebBrowserOptions } from "./WebBrowser";

export type ImagineOptions = {
  /** Fixed white temperature for every output, in kelvin; replaces scheduled night light. */
  readonly displayTemperature?: number;
  readonly applications?: ApplicationsOptions;
  readonly floating?: FloatingOptions;
  readonly keybindings?: ShellKeybindings;
  readonly policy?: AgencyPolicy;
  /** Optional client viewer. Disabled unless a reviewed launcher is supplied. */
  readonly ambientChat?: AmbientChatOptions;
  readonly chatWindow?: ChatWindowOptions;
  readonly webBrowser?: WebBrowserOptions;
  readonly sessionCatalogue?: import("./SessionCatalogue").CatalogueOptions;
  readonly layoutPersistence?: import("./useLayoutPersistence").LayoutPersistenceOptions;
};
