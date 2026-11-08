// Merge into Imagine's existing reviewed key table, before ownedChords().
// This adds no window/workspace reducer or client DSH Host.
import { exec } from '@domicile-desktop/manganese-window-management/keyboard/commands';
export const nativeKittyBindings = {
  'Meta+Return': exec('agency-kitty', 'desktop', 'terminal'),
  'Meta+Control+Shift+Return': exec('agency-kitty', 'menu'),
  'Meta+Shift+Return': exec('agency-kitty', 'desktop', 'rescue'),
};
