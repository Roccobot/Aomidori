"use strict";
/* Feedback document, navigation. Third of the four page scripts (see feedback-data.js).
   The mobile editing state, the sticky strip, moving between cards and the floating
   buttons with their long press. Uses the cards and the Altro overlay of feedback-ui.js. */
// --- Mobile editing: only Salva while a text field is focused ---
const isMobileUi = () => window.matchMedia("(max-width: 720px)").matches;
let editingHoldTimer = null;
function setEditingMobile(on) {
  if (!isMobileUi()) {
    document.body.classList.remove("editing-mobile");
    return;
  }
  document.body.classList.toggle("editing-mobile", on);
}
function holdEditingAfterSave() {
  clearTimeout(editingHoldTimer);
  setEditingMobile(true);
  editingHoldTimer = setTimeout(() => {
    const active = document.activeElement;
    const still =
      active &&
      (active.matches("textarea, input:not([type=file]), .rich-editor") ||
        active.closest?.(".rich-editor"));
    if (!still) setEditingMobile(false);
  }, 5000);
}
document.addEventListener(
  "focusin",
  (event) => {
    const t = event.target;
    if (!t) return;
    if (
      t.matches?.("textarea:not([readonly]), input:not([type=file]):not([readonly]), .rich-editor") ||
      t.closest?.(".rich-editor")
    )
      setEditingMobile(true);
  },
  true,
);
document.addEventListener(
  "focusout",
  () => {
    clearTimeout(editingHoldTimer);
    editingHoldTimer = setTimeout(() => {
      const active = document.activeElement;
      const still =
        active &&
        (active.matches?.("textarea:not([readonly]), input:not([type=file]):not([readonly]), .rich-editor") ||
          active.closest?.(".rich-editor"));
      if (!still) setEditingMobile(false);
    }, 0);
  },
  true,
);
window.feedbackHoldEditingAfterSave = holdEditingAfterSave;
// Anchor the next card below the actual sticky dashboard, including wrapped mobile text.
const responseCards = Array.from(document.querySelectorAll(".test, .extra"));
const previousCard = document.querySelector("#previous-card");
const nextCard = document.querySelector("#next-card");
const firstEmpty = document.querySelector("#first-empty");
const dashboard = document.querySelector(".dashboard");
// On desktop the counts live at the top of Altro, and the page has no fixed strip (the user's
// request, 2026-10-06: *sparisce del tutto la striscia cloud, e il caricatore con le info va a
// vivere sopra 'Altro', nello stesso riquadro*). Elsewhere the strip stays where the page has it.
const desktopUi = window.matchMedia("(min-width: 1100px)");
const dashboardHome = document.createComment("dashboard");
dashboard.before(dashboardHome);
function placeDashboard() {
  const altro = document.querySelector("#extra-section");
  if (desktopUi.matches && altro) altro.prepend(dashboard);
  else dashboardHome.after(dashboard);
}
placeDashboard();
function refreshDashboardDocked() {
  // Sticky positioning is not exposed as a CSS state. The viewport edge is the
  // reliable boundary between the normal floating strip and its docked state.
  dashboard.classList.toggle("is-docked", dashboard.getBoundingClientRect().top <= 0);
}
// On desktop nothing is fixed above the cards, so a card lands where Altro's top is.
function navigationOffset() {
  if (desktopUi.matches) return DESKTOP_TOP;
  return dashboard.getBoundingClientRect().height + 12;
}
const DESKTOP_TOP = 18;
function currentCardIndex() {
  const cards = responseCards;
  const offset = navigationOffset();
  const tops = cards.map((card) => card.getBoundingClientRect().top);
  let index = -1;
  for (let i = 0; i < cards.length; i++) {
    if (tops[i] <= offset + 2) index = i;
    else break;
  }
  // A section heading between cards belongs to the upcoming visible card.
  if (index >= 0 && index < cards.length - 1 &&
      cards[index].getBoundingClientRect().bottom < offset) index++;
  // Sticky Altro sits beside the proofs. If a proof is actually at the
  // offset, that proof is current. Altro stays current only past the proofs.
  if (index >= 0 && cards[index].classList.contains("extra")) {
    let proof = -1;
    let best = -Infinity;
    for (let i = 0; i < index; i++) {
      if (cards[i].classList.contains("extra")) continue;
      if (tops[i] <= offset + 2 && tops[i] > best) {
        best = tops[i];
        proof = i;
      }
    }
    if (proof >= 0 && tops[proof] > offset - 80) index = proof;
  }
  return index;
}
function firstEmptyCard() {
  return responseCards.find(card => !card.classList.contains("extra") && !card.classList.contains("has-response"));
}
// The card the next key goes to, or nothing when it cannot move the page down.
// On desktop Altro is the sticky side column: going to it shifted the page by a few pixels
// and the following press shifted it back (the user's report, 2026-10-05), so past the last
// proof there is no next. The page already at its bottom has no next either.
function nextTarget(index) {
  const card = responseCards[index + 1];
  if (!card) return null;
  if (!isMobileUi() && card.classList.contains("extra")) return null;
  const bottom = document.documentElement.scrollHeight - window.innerHeight;
  if (window.scrollY >= bottom - 2) return null;
  return card;
}
function refreshNavigation() {
  refreshDashboardDocked();
  const index = currentCardIndex();
  previousCard.disabled = !loaded || index <= 0;
  nextCard.disabled = !loaded || !nextTarget(index);
  // A button that cannot act leaves the pill, which shortens with it.
  previousCard.hidden = previousCard.disabled;
  nextCard.hidden = nextCard.disabled;
  const empty = firstEmptyCard();
  // On mobile ⇥ stays visible, so a long press opens Altro even when nothing is empty.
  const mobile = isMobileUi();
  const floatingSave = document.querySelector("#floating-save");
  if (mobile) {
    firstEmpty.hidden = false;
    firstEmpty.title = empty
      ? "Primo riquadro non compilato · tieni premuto per Altro"
      : "Tieni premuto per Altro";
    firstEmpty.setAttribute(
      "aria-label",
      empty
        ? "Primo riquadro non compilato. Tieni premuto per aprire Altro"
        : "Tieni premuto per aprire Altro",
    );
  } else {
    firstEmpty.hidden = !empty || responseCards[index] === empty;
    firstEmpty.title = "Primo riquadro non compilato";
    firstEmpty.setAttribute("aria-label", "Primo riquadro non compilato");
  }
  floatingSave.title = mobile ? "Salva · tieni premuto per Altro" : "Salva le risposte";
  floatingSave.setAttribute(
    "aria-label",
    mobile ? "Salva le risposte. Tieni premuto per aprire Altro" : "Salva le risposte",
  );
  firstEmpty.disabled = !loaded;
  document.documentElement.style.setProperty("--feedback-scroll-offset", navigationOffset() + "px");
}
function goToCard(card) {
  if (!card) return;
  window.scrollTo({top: window.scrollY + card.getBoundingClientRect().top - navigationOffset(), behavior: "instant"});
  document.querySelector("#navigation-position").textContent =
    card.querySelector(".check-position")?.textContent || card.querySelector("h3,h2").textContent;
  refreshNavigation();
}
previousCard.addEventListener("click", () => goToCard(responseCards[currentCardIndex() - 1]));
nextCard.addEventListener("click", () => goToCard(nextTarget(currentCardIndex())));
// On mobile a long press opens the Altro overlay; a short tap keeps the button's own action.
function onTapOrHold(button, tap) {
  let held = false, timer = null;
  const clear = () => { clearTimeout(timer); timer = null; };
  button.addEventListener("pointerdown", (event) => {
    if (!isMobileUi() || event.button != null && event.button !== 0) return;
    held = false;
    clear();
    timer = setTimeout(() => {
      held = true;
      setAltroOverlayOpen(true);
    }, 450);
  });
  for (const name of ["pointerup", "pointercancel", "pointerleave"]) button.addEventListener(name, clear);
  button.addEventListener("click", (event) => {
    if (held) {
      event.preventDefault();
      event.stopImmediatePropagation();
      held = false;
      return;
    }
    tap();
  });
}
onTapOrHold(firstEmpty, () => {
  const empty = firstEmptyCard();
  if (empty) goToCard(empty);
  else if (isMobileUi()) {
    const target = document.querySelector("#extra-section");
    target?.scrollIntoView({ behavior: "smooth", block: "start" });
  }
});
let navigationFrame = null;
window.addEventListener("scroll", () => {
  if (navigationFrame !== null) return;
  navigationFrame = requestAnimationFrame(() => {
    navigationFrame = null;
    refreshNavigation();
  });
}, {passive: true});
new ResizeObserver(refreshNavigation).observe(document.querySelector(".dashboard"));
desktopUi.addEventListener("change", () => { placeDashboard(); refreshNavigation(); });
onTapOrHold(document.querySelector("#floating-save"), saveByHand);
