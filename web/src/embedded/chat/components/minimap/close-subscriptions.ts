import { isUserMessage } from '../../types/history';
import type { MinimapCloseSubscription } from './minimap';

export const closeOnUserHistoryMessageAdded: MinimapCloseSubscription =
  close => {
    const subscribe = window.jsb?.MessagesBridge?.onHistoryMessageAdded;
    if (!subscribe) {
      return;
    }

    return subscribe(message => {
      if (isUserMessage(message)) {
        close();
      }
    });
  };
