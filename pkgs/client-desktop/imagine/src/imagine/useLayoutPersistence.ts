import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { projectSnapshot } from "./ipc/snapshot";
import type { Snapshot } from "./ipc/snapshot";
import { runHelperRequest } from "./HelperRequest";
import { restoreLayout } from "./LayoutRestore";

export type LayoutPersistenceOptions = { readonly identity: string; readonly restartRecovery?: boolean };
export type LayoutRestoreAction = { readonly restoreLayout: true; readonly snapshot: Snapshot };
/** A process-incarnation key prevents reused native IDs matching an old desktop. */
async function identity(domicile: Domicile, helper: string) {
  if (!helper || /[\s\0?#]/u.test(helper) || helper.includes("://")) throw Error("Invalid layout helper");
  const value = await runHelperRequest(domicile, [helper], {}, 5000);
  if (value.version !== 1 || !/^[a-f0-9]{64}$/.test(value.key)) throw Error("Invalid layout identity");
  return value.key as string;
}

export function useLayoutPersistence(domicile: Domicile, state: WindowState, described: boolean,
  config: LayoutPersistenceOptions | undefined, dispatch: (action: LayoutRestoreAction) => void) {
  const [loaded, setLoaded] = useState<{ key: string; snapshot?: Snapshot }>();
  const [ready, setReady] = useState(config === undefined);
  const [error, setError] = useState<string>();
  const failed = useRef(false);
  const current = useRef(state); current.current = state;
  useEffect(() => {
    if (config === undefined) return;
    let disposed = false;
    void (async () => {
      const key = await identity(domicile, config.identity);
      const value = (await domicile.files.readText(`.local/state/imagine/layout-${key}.json`)).match({
        Ok: text => { if (text.length > 8 * 1024 * 1024) throw Error("Saved layout limit"); return JSON.parse(text); }, Err: () => undefined,
      });
      if (value && (value.version !== 1 || value.identity !== key)) throw Error("Saved layout identity mismatch");
      if (!disposed) setLoaded({ key, snapshot: value?.snapshot });
    })().catch(() => { if (!disposed) { setError("Layout retention is unavailable"); setReady(true); } });
    return () => { disposed = true; };
  }, [domicile, config]);
  useLayoutEffect(() => {
    if (ready || loaded === undefined || !described || domicile.browser.windows === undefined) return;
    // Both retained window lists must have reached the reducer before restore.
    const ids = new Set(state.windows.map(w => w.id));
    if (domicile.windows.list.some(w => !ids.has("app:" + w.appId)) || domicile.browser.windows.some(w => !ids.has("browser:" + w.id))) return;
    if (loaded.snapshot !== undefined) {
      try { restoreLayout(state, loaded.snapshot); dispatch({ restoreLayout: true, snapshot: loaded.snapshot }); }
      catch { failed.current = true; setError("Saved layout was rejected; the saved file is kept"); }
    }
    setReady(true);
  }, [ready, loaded, described, domicile, state, dispatch]);
  const writing = useRef(false), signature = useRef("");
  useEffect(() => {
    if (!ready || loaded === undefined) return;
    let disposed = false;
    const save = async () => {
      if (writing.current || disposed || failed.current || domicile.session.locked !== false) return;
      const snapshot = projectSnapshot({ state: current.current, screens: [], browsers: domicile.browser.windows });
      const text = JSON.stringify({ version: 1, identity: loaded.key, snapshot });
      if (text === signature.current) return;
      writing.current = true;
      try {
        const result = await domicile.files.write(`.local/state/imagine/layout-${loaded.key}.json`, text, { atomic: true });
        result.match({ Ok: () => { signature.current = text; }, Err: () => { if (!disposed) setError("Layout could not be saved"); } });
      } finally { writing.current = false; }
    };
    const attempt = () => { void save().catch(() => { if (!disposed) setError("Layout could not be saved"); }); };
    const timer = setInterval(attempt, 250); attempt();
    return () => { disposed = true; clearInterval(timer); };
  }, [ready, loaded, domicile]);
  return { ready, error, identity: loaded?.key };
}
