// Imagine's own shell entry. The reference package is kept separately in
// reference/manganese and is never mounted by this implementation.
import "@domicile-desktop/component-library/fonts/inter.css";
import "./styles/manganese-75708d7.css";

import { runImagine } from "./imagine/ImagineShell";

export { runImagine };
export type { ImagineOptions } from "./imagine/ImagineOptions";
export { options } from "./imagine/options";
export type { AgencyPolicy as ImaginePolicy } from "./imagine/policy";

/** Domicile's standard shell-module entry, using Imagine's own desktop. */
export const Shell = runImagine();
