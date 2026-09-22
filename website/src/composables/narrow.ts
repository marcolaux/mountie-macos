/**
 * Whether the page is on a phone-sized viewport. Below this width every
 * product frame swaps its desktop mock for the phone one: a visitor on a
 * phone is looking at the app they would install, not a shrunken window.
 * One breakpoint, the same one the layout stacks at (48rem).
 */
import { onBeforeUnmount, ref } from "vue";

const QUERY = "(max-width: 48rem)";

export function useNarrow() {
  const narrow = ref(false);
  if (typeof window !== "undefined" && typeof window.matchMedia === "function") {
    const mq = window.matchMedia(QUERY);
    narrow.value = mq.matches;
    const on = (e: MediaQueryListEvent) => (narrow.value = e.matches);
    mq.addEventListener("change", on);
    onBeforeUnmount(() => mq.removeEventListener("change", on));
  }
  return narrow;
}
