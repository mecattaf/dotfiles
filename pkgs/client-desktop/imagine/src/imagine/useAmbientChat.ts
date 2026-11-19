import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { useEffectEvent, useLayoutEffect, useRef } from "react";
import { createAmbientChat } from "./AmbientChat";
import type { AmbientChatConfig, AmbientTransition } from "./AmbientChat";

/** Optional adapter only. It never owns a DSH service or subscribes to commands. */
export const useAmbientChat = ({ domicile, config, state, blocked, transition }: {
  domicile: Domicile;
  config: AmbientChatConfig | undefined;
  state: WindowState;
  blocked: boolean;
  transition: (update: AmbientTransition) => void;
}) => {
  const latest = useRef({ state, blocked });
  const control = useRef<ReturnType<typeof createAmbientChat> | undefined>(undefined);
  useLayoutEffect(() => {
    latest.current = { state, blocked };
    control.current?.reconcile();
  }, [state, blocked]);
  useLayoutEffect(() => {
    if (config === undefined) return;
    const current = createAmbientChat(config, {
      read: () => ({ ...latest.current, browsers: domicile.browser.windows }),
      transition,
      launch: async (argv) => {
        const result = await domicile.processes.run(argv);
        const success = result.match({ Ok: (value) => value.code === 0 && value.signal === undefined, Err: () => false });
        // The helper owns SSH/bootstrap/native errors. Never echo captured
        // output or an SDK error body that could contain browser credentials.
        if (!success) throw Error("ambient launcher failed");
      },
      report: (message) => console.error(message),
    });
    control.current = current;
    const stop = domicile.browser.on("change", current.reconcile);
    return () => { stop(); current.dispose(); if (control.current === current) control.current = undefined; };
  }, [config, domicile, transition]);
  return {
    command: useEffectEvent((args: readonly string[]): boolean => {
      if (args[0] !== "ambient-chat") return false;
      if (control.current === undefined) console.error("Imagine ambient chat is disabled");
      else control.current.command(args);
      return true;
    }),
    consumesFocusRequest: useEffectEvent((id: string): boolean => control.current?.consumesFocusRequest(id) ?? false),
  };
};
