// Media-key notice wiring adapted from Manganese 67c29a9, MIT (LICENSE).
// Stock notice components/audio controls; Agency's tested DRM and MPRIS APIs.
import { AnimatedMicrophoneIcon } from "@domicile-desktop/component-library/AnimatedMicrophoneIcon";
import { AnimatedSpeakerIcon } from "@domicile-desktop/component-library/AnimatedSpeakerIcon";
import { useScreenRegion } from "@domicile-desktop/component-library/DisplayProvider";
import { ChoiceToast, LevelToast } from "@domicile-desktop/component-library/LevelToast";
import { inhibitIdle } from "@domicile-desktop/manganese-bar-module-idle-inhibitor/portal-inhibit";
import { useVolumeKeys } from "@domicile-desktop/manganese-bar-module-volume/useVolumeKeys";
import { MediaKey } from "@domicile-desktop/manganese-window-management/keyboard/media-key";
import { casting } from "@domicile-desktop/sdk/cast";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { deskSound } from "@domicile-desktop/system-audio/react";
import { TOAST_LAYER } from "../styles/layers";
import { useEffect, useMemo, useState } from "react";
import { createBrightnessController } from "./brightness";
import { createMediaController } from "./media";
import type { MediaAction } from "./media";

type Level = { kind: "Volume" | "Microphone" | "Brightness"; level: number; muted: boolean };
export const useMediaNotices = (domicile: Domicile) => {
  const volume = useVolumeKeys(deskSound(domicile));
  const brightness = useMemo(() => createBrightnessController(domicile), [domicile]);
  const player = useMemo(() => createMediaController(domicile), [domicile]);
  useEffect(() => () => { brightness.dispose(); player.dispose(); }, [brightness, player]);
  const [press, setPress] = useState<{ count: number; level: Level }>();
  const [choice, setChoice] = useState<{ count: number; label: string; value: string; detail?: string }>();
  const unavailable = (label: string, message: string) => {
    console.error(`Agency ${label}: ${message}`);
    setChoice((last) => ({ count: (last?.count ?? 0) + 1, label, value: "Unavailable", detail: message }));
  };
  const showLevel = (level: Level) => {
    setChoice(undefined);
    setPress((last) => ({ count: (last?.count ?? 0) + 1, level }));
  };
  const requestBrightness = (action: "up" | "down" | "max" | "toggle", fine = false) => {
    const requested = action === "max" ? brightness.set(1)
      : action === "toggle" ? brightness.toggle() : brightness.step(action, fine ? 2 : 10);
    void requested.then((level) => {
      if (level === undefined) unavailable("Brightness", "No eligible internal DRM backlight");
      else showLevel({ kind: "Brightness", level: level.level, muted: level.muted });
    }).catch((error: unknown) => unavailable("Brightness", String(error)));
  };
  return {
    press,
    choice,
    requestBrightness,
    requestMedia: (action: MediaAction) => {
      void player.press(action).then((snapshot) => {
        if (snapshot === undefined) { unavailable("Media", "No eligible MPRIS player"); return; }
        setPress(undefined);
        setChoice((last) => ({ count: (last?.count ?? 0) + 1, label: "Media", value: snapshot.status,
          detail: [snapshot.title, snapshot.artists.join(", ")].filter(Boolean).join(" · ") || snapshot.player }));
      }).catch((error: unknown) => unavailable("Media", String(error)));
    },
    pressKey: (key: MediaKey) => {
      let asked: { level: number; muted: boolean } | undefined;
      let kind: Level["kind"] = "Volume";
      switch (key) {
        case MediaKey.VolumeUp: asked = volume.up(); break;
        case MediaKey.VolumeDown: asked = volume.down(); break;
        case MediaKey.VolumeMute: asked = volume.mute(); break;
        case MediaKey.MicMute: kind = "Microphone"; asked = volume.micMute(); break;
        case MediaKey.BrightnessUp:
        case MediaKey.BrightnessDown: {
          requestBrightness(key === MediaKey.BrightnessUp ? "up" : "down");
          return;
        }
      }
      if (asked !== undefined) {
        showLevel({ ...asked, kind });
      } else unavailable(kind, "The default audio device is not available");
    },
  };
};

export const NativeNotices = ({ screen, press, choice, keymap }: {
  screen: string;
  press: ReturnType<typeof useMediaNotices>["press"];
  choice: ReturnType<typeof useMediaNotices>["choice"];
  keymap: { count: number; name: string; description?: string | undefined } | undefined;
}) => {
  const region = useScreenRegion(screen);
  return <div style={{ ...region, position: "fixed", display: "flex", justifyContent: "center",
    alignItems: "flex-end", paddingBottom: 20, pointerEvents: "none", zIndex: TOAST_LAYER }}>
    {press !== undefined && <LevelToast changes={press.count}
      label={press.level.kind} level={press.level.level} muted={press.level.muted}
      icon={press.level.kind === "Volume"
        ? <AnimatedSpeakerIcon muted={press.level.muted} volume={press.level.level} size={28} weight="fill" />
        : press.level.kind === "Microphone"
          ? <AnimatedMicrophoneIcon muted={press.level.muted} size={28} weight="fill" />
          : <span aria-hidden="true" style={{ fontSize: 28 }}>☀</span>} />}
    {choice !== undefined && <ChoiceToast changes={choice.count} label={choice.label}
      choice={choice.value} detail={choice.detail} icon={<span aria-hidden="true" style={{ fontSize: 28 }}>♪</span>} />}
    {keymap !== undefined && <ChoiceToast changes={keymap.count} label="Keymap"
      choice={keymap.name} detail={keymap.description} icon={<span aria-hidden="true" style={{ fontSize: 28 }}>⌨</span>} />}
  </div>;
};

/** Match stock privacy/idle policy while casting, releasing only our inhibitor. */
export const useCasting = (domicile: Domicile) => {
  const [active, setActive] = useState(false);
  useEffect(() => {
    let held: ReturnType<typeof inhibitIdle> | undefined;
    const release = () => {
      const previous = held;
      held = undefined;
      void previous?.then((result) => result.match({
        Err: (error) => console.error("Agency idle inhibitor refused", error),
        Ok: (release) => { void release(); },
      }));
    };
    const stop = casting(domicile).watch((running) => {
      const on = running.length > 0;
      if (on && held === undefined) held = inhibitIdle(domicile.dbus, "Casting to a TV");
      else if (!on) release();
      setActive(on);
    });
    return () => { stop(); release(); };
  }, [domicile]);
  return active;
};
