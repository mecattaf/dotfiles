/** Owned browser policy; argv stays separate from launcher/clipboard content. */
export type WebBrowserOptions = { readonly command: readonly string[] };
export const externalWebCommand = (browser: WebBrowserOptions | undefined, url: string, isPrivate: boolean): readonly string[] | undefined => {
  if (browser === undefined || !/^https?:\/\//i.test(url)) return undefined;
  if (browser.command.length === 0 || browser.command.some((word) => !word || word.includes("\0"))) {
    throw Error("An external web browser requires a fixed command");
  }
  return [...browser.command, ...(isPrivate ? ["--incognito"] : []), "--", url];
};
