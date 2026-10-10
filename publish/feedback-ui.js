"use strict";
/* Feedback document, interface. Second of the four page scripts (see feedback-data.js).
   Theme, messages, counters, cards and attachments, the Altro fields and overlay, and the
   six Consegna commands. Uses the data and save() from feedback-data.js; refreshCounts()
   calls refreshNavigation() from feedback-nav.js at run time. */
/* DF theme: on load it follows the system; T (no modifiers, outside the fields)
   switches light and dark for this session only. Nothing is stored, so a reload
   goes back to the system theme. */
const toggleTheme = (function initFeedbackTheme() {
  let override = null;
  const mq = window.matchMedia("(prefers-color-scheme: dark)");
  function effective() {
    return override || (mq.matches ? "dark" : "light");
  }
  function apply() {
    document.documentElement.setAttribute("data-theme", effective());
  }
  function onSystemChange() {
    if (override === null) apply();
  }
  if (mq.addEventListener) mq.addEventListener("change", onSystemChange);
  else if (mq.addListener) mq.addListener(onSystemChange);
  apply();
  return function toggleTheme() {
    override = effective() === "dark" ? "light" : "dark";
    apply();
  };
})();
// Messages of the commands, in the strip under the save status.
const message = document.querySelector("#action-message");
function el(tag, text, cls) {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  if (cls) e.className = cls;
  return e;
}
function attachmentEntry(card) {
  return card.classList.contains("extra") ? draft.extra : entry(card.dataset.id);
}
function strokeIcon(paths) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "2");
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");
  for (const d of paths) {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", d);
    svg.append(path);
  }
  return svg;
}
function labelA11yIcon() {
  const svg = strokeIcon([
    "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z",
    "M12 8.2a1.15 1.15 0 1 0 0-2.3 1.15 1.15 0 0 0 0 2.3z",
    "M8.2 11.2h7.6",
    "M12 11.2v3.1",
    "M12 14.3 9.6 18.4",
    "M12 14.3l2.4 4.1",
  ]);
  svg.setAttribute("class", "label-a11y");
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label", "Solo lettore di schermo");
  return svg;
}
function report(text, error = false) {
  message.textContent = text;
  message.classList.toggle("error", error);
}
// A notice that rises at the bottom of the page and fades after a few seconds, for the
// outcomes the user waits for after a tap (Invia, since 2026-10-04: there was no visible
// answer). The same words go to report(), which screen readers hear.
let toastTimer = null;
function toast(text, error = false) {
  let box = document.querySelector(".toast");
  if (!box) {
    box = el("div", undefined, "toast");
    box.setAttribute("aria-hidden", "true");
    document.body.append(box);
  }
  box.textContent = text;
  box.classList.toggle("is-error", error);
  // Restart the entrance when a second notice replaces the first.
  box.classList.remove("is-visible");
  void box.offsetWidth;
  box.classList.add("is-visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => box.classList.remove("is-visible"), TOAST_MS);
}
const TOAST_MS = 4000;
function countIcon(kind) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  svg.setAttribute("class", "count-icon count-" + kind);
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  // Material-like: check / alert / cancel (no emoji).
  path.setAttribute("d", {
    ok: "M9.2 16.6 4.8 12.2l1.4-1.4 3 3 8-8 1.4 1.4z",
    warn: "M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z",
    bad: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm3.5 13.1-1.4 1.4L12 13.4l-2.1 2.1-1.4-1.4L10.6 12 8.5 9.9l1.4-1.4L12 10.6l2.1-2.1 1.4 1.4L13.4 12l2.1 2.1z",
  }[kind]);
  svg.append(path);
  return svg;
}
function countChip(kind, label, value) {
  const chip = el("span", undefined, "count-chip count-chip-" + kind);
  chip.append(countIcon(kind), el("span", String(value)));
  chip.title = label + ": " + value;
  chip.setAttribute("aria-label", label + ": " + value);
  return chip;
}
function refreshCounts() {
  for (const card of document.querySelectorAll(".test")) {
    const value = entry(card.dataset.id);
    card.dataset.outcome = value.status;
    card.dataset.outcomeKind = spec.outcomes.find((outcome) => outcome.label === value.status)?.kind || "";
    card.classList.toggle("has-response", Boolean(value.status || value.comment.trim() || value.images.length));
  }
  for (const card of document.querySelectorAll(".question")) {
    const value = draft.decisions[card.dataset.id];
    card.classList.toggle("has-response", Boolean(value && (value.choice || value.comment.trim())));
  }
  for (const card of document.querySelectorAll(".label-card")) {
    const item = labelById(card.dataset.id);
    const dirty = item ? labelDirty(item) : false;
    card.classList.toggle("has-response", dirty);
    const dot = card.querySelector(".label-modified");
    if (dot) dot.hidden = !dirty;
  }
  const counters = Object.fromEntries(outcomes.map((o) => [o, 0]));
  let done = 0;
  for (const item of spec.items) {
    const status = entry(item.id).status;
    if (status) {
      counters[status]++;
      done++;
    }
  }
  const counts = document.querySelector("#counts");
  const ratio = el("span", `${done}/${spec.items.length}`, "count-ratio");
  ratio.id = "count-answered";
  ratio.setAttribute("aria-label", `Riscontri: ${done} su ${spec.items.length}`);
  counts.replaceChildren(
    ratio,
    ...spec.outcomes.map((outcome) => countChip(outcome.kind, outcome.label, counters[outcome.label])),
  );
  document.querySelector("#progress").value = done;
  refreshNavigation();
}

function hydrate() {
  for (const card of document.querySelectorAll(".test")) {
    const value = entry(card.dataset.id);
    card.querySelector(".comment").value = value.comment;
    for (const b of card.querySelectorAll(".outcome"))
      b.setAttribute("aria-pressed", String(b.dataset.status === value.status));
    drawAttachments(card);
  }
  for (const card of document.querySelectorAll(".question")) {
    const value = draft.decisions[card.dataset.id] || { choice: "", comment: "" };
    card.querySelector(".question-comment").value = value.comment;
    for (const b of card.querySelectorAll(".choice"))
      b.setAttribute("aria-pressed", String(b.dataset.choice === value.choice));
  }
  for (const card of document.querySelectorAll(".label-card")) {
    const item = labelById(card.dataset.id);
    if (!item) continue;
    card.querySelector("textarea").value = labelShown(item);
  }
  document.querySelector("#notes").value = draft.notes;
  syncDevices();
  syncInstalledConfirm();
  syncAltroFields();
  drawAttachments(document.querySelector(".extra"));
  window.feedbackFormatting?.refresh();
  refreshCounts();
  const lab = document.querySelector("#labels");
  if (lab) lab.hidden = !(spec.labels && spec.labels.length);
}
// The object URLs each attachment list shows, released when the list is drawn again: an
// unreleased URL keeps its file in memory for as long as the page is open.
const shownUrls = new WeakMap();
/* Where a card's attachments are drawn: its own list, and for Altro also the one under the
   mobile overlay's field (the user's request, 2026-10-06: *voglio vedere gli allegati ad
   'Altro' nell'overlay mobile*). Each list makes its own object URLs. */
function attachmentLists(card) {
  const own = card.querySelector(".image-list");
  const overlay = card.classList.contains("extra") ? document.querySelector("#altro-overlay .image-list") : null;
  return overlay ? [own, overlay] : [own];
}
/* Rinomina and Elimina carry an icon and their words: on a phone only the icon shows, on a
   desktop the icon comes before the words (the user's requests, 2026-10-06), and the name stays
   the label a screen reader says. */
function attachmentButton(label, paths) {
  const button = el("button");
  button.type = "button";
  button.title = label;
  button.setAttribute("aria-label", label);
  const icon = strokeIcon(paths);
  icon.setAttribute("aria-hidden", "true");
  button.append(icon, el("span", label, "attachment-action-text"));
  return button;
}
function drawAttachments(card) {
  for (const list of attachmentLists(card)) drawAttachmentList(card, list);
}
function drawAttachmentList(card, list) {
  for (const url of shownUrls.get(list) || []) URL.revokeObjectURL(url);
  const urls = [];
  shownUrls.set(list, urls);
  list.replaceChildren();
  const inOverlay = Boolean(list.closest("#altro-overlay"));
  attachmentEntry(card).images.forEach((img, index) => {
    const figure = el("figure");
    const url = URL.createObjectURL(img.blob);
    urls.push(url);
    if (img.type === "application/zip") {
      const download = el("a", "Scarica ZIP", "zip-download");
      download.href = url;
      download.download = img.name;
      figure.append(el("span", "ZIP", "file-kind"), el("figcaption", img.name), download);
    } else {
      const image = el("img");
      image.src = url;
      image.alt = img.name;
      figure.append(image, el("figcaption", img.name));
    }
    /* While a field is being written in, a click on the attachment writes its name, with the
       extension, at the caret as inline code (the user's request, 2026-10-05, and as code and
       not between quotes since 2026-10-06). The press is held back so the field keeps the focus
       and the caret; the two buttons, the ZIP link and the rename field keep their own click.
       In the mobile overlay a tap with no field being written in copies the name to the
       clipboard, between backticks (the user's request, 2026-10-06): with the keyboard closed
       the field may have lost the caret. */
    figure.title = inOverlay
      ? "Un tocco inserisce il nome nel testo, o lo copia negli appunti"
      : "Mentre scrivi, un clic qui inserisce il nome nel testo";
    figure.addEventListener("pointerdown", (event) => {
      if (event.target.closest("button, a, input")) return;
      if (window.feedbackFormatting?.writing()) event.preventDefault();
    });
    figure.addEventListener("click", async (event) => {
      if (event.target.closest("button, a, input")) return;
      if (window.feedbackFormatting?.insertCodeAtCaret(img.name) || !inOverlay) return;
      try {
        await copyText("`" + img.name + "`");
        toast("Copiato negli appunti: " + img.name);
      } catch {
        toast("Copia non riuscita.", true);
      }
    });
    // Rinomina and Elimina, the user's words since 2026-10-06 ('Rimuovi' until that evening),
    // on one centred row.
    const rename = attachmentButton("Rinomina", ["M12 20h9", "M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"]);
    rename.addEventListener("click", () => renameAttachment(card, index, figure));
    const remove = attachmentButton("Elimina", ["M3 6h18", "M8 6V4h8v2", "M19 6l-1 14H6L5 6", "M10 11v6M14 11v6"]);
    remove.addEventListener("click", () => {
      attachmentEntry(card).images.splice(index, 1);
      drawAttachments(card);
      changed();
    });
    const actions = el("div", "", "attachment-actions");
    actions.append(rename, remove);
    figure.append(actions);
    list.append(figure);
  });
}
/* Renames an attachment after it was loaded (the user's request, 2026-10-05). Only the name
   changes: the original bytes, and on the cloud their storageKey, stay as they are.
   Since 2026-10-06 (his request: *voglio digitare un nome e poi Invio, senza preoccuparmi delle
   estensioni*) the name is edited in place, in a field that holds the name alone, with the
   extension beside it and out of reach: Invio or leaving the field confirms, Esc cancels. */
function renameAttachment(card, index, figure) {
  const image = attachmentEntry(card).images[index];
  const caption = figure.querySelector("figcaption");
  if (!image || !caption) return;
  const dot = image.name.lastIndexOf(".");
  const extension = dot > 0 ? image.name.slice(dot) : "";
  const field = el("input", "", "attachment-rename-name");
  field.type = "text";
  field.value = extension ? image.name.slice(0, dot) : image.name;
  field.setAttribute("aria-label", "Nome dell'allegato, senza estensione");
  const editing = el("div", "", "attachment-rename");
  editing.append(field, el("span", extension, "attachment-rename-extension"));
  caption.replaceWith(editing);
  let done = false;
  const finish = (keep) => {
    if (done) return;
    done = true;
    let name = field.value.trim();
    // A name typed with its extension does not get a second one.
    if (extension && name.toLowerCase().endsWith(extension.toLowerCase())) name = name.slice(0, -extension.length).trim();
    if (!keep || name + extension === image.name) { drawAttachments(card); return; }
    if (!name || /[\\/\u0000-\u001f]/.test(name) || (name + extension).length > 500) {
      report("Il nome non può essere vuoto, contenere barre o superare i 500 caratteri.", true);
      drawAttachments(card);
      return;
    }
    image.name = name + extension;
    drawAttachments(card);
    changed();
    report("Allegato rinominato: " + image.name + ".");
  };
  field.addEventListener("keydown", (event) => {
    if (event.key === "Enter") { event.preventDefault(); finish(true); }
    else if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); finish(false); }
  });
  field.addEventListener("blur", () => finish(true));
  field.focus();
  field.select();
}
function changed() {
  revision++;
  draft.completed = null;
  refreshCounts();
  clearTimeout(saveTimer);
  saveTimer = setTimeout(save, 350);
  saved.textContent = "Modifiche da salvare...";
}
// Copy a text to the clipboard, with the selection fallback for browsers that refuse the API.
// With [html], the rich copy goes along, for the apps that read it.
async function copyText(text, html) {
  try {
    if (html && window.ClipboardItem) {
      await navigator.clipboard.write([new ClipboardItem({
        "text/plain": new Blob([text], {type: "text/plain"}),
        "text/html": new Blob([html], {type: "text/html"}),
      })]);
    } else {
      await navigator.clipboard.writeText(text);
    }
  } catch {
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.setAttribute("aria-hidden", "true");
    area.tabIndex = -1;
    area.style.position = "fixed";
    area.style.top = "0";
    area.style.left = "0";
    area.style.opacity = "0";
    document.body.append(area);
    area.focus();
    area.select();
    try {
      if (!document.execCommand("copy")) throw Error("Copia non riuscita.");
    } finally {
      area.remove();
    }
  }
}
async function copy() {
  try {
    await copyText(summary());
    report("Riepilogo copiato. Incollalo in chat con gli eventuali allegati.");
  } catch {
    report("Il browser non ha permesso la copia negli appunti: esporta le risposte.", true);
  }
}
function copyLabelId(id) {
  copyText(String(id || "").toLowerCase()).catch(() => {});
}
for (const item of spec.labels || []) {
  const card = el("article", undefined, "card label-card");
  card.dataset.id = item.id;
  const title = el("h3", item.title);
  const dot = el("span", undefined, "label-modified");
  dot.hidden = true;
  dot.setAttribute("aria-label", "modificato");
  title.append(dot);
  const idCopy = el("button", String(item.id).toLowerCase(), "label-id");
  idCopy.type = "button";
  idCopy.addEventListener("click", () => {
    copyLabelId(item.id);
  });
  card.append(idCopy, title);
  if (item.a11y) card.append(labelA11yIcon());
  const label = el("label", item.title, "sr-only");
  const field = el("textarea");
  field.className = "label-revision";
  field.rows = 3;
  field.value = item.proposal;
  field.addEventListener("input", () => {
    writeLabel(item, field.value);
    changed();
  });
  label.append(field);
  card.append(label);
  document.querySelector("#label-list").append(card);
}
/* The copy mark at the top right of every card (the user's request, 2026-10-09, with his mockup
   and his icon): a tap copies the card's reference (`4.90-05`, `d-velo-pannello`,
   `e-draw_panel`), to quote it in another comment, lower case like the label ids.
   ⚠️ As inline code (his request of the same day, after the first version: *formattato come
   codice in linea e che appaia come tale quando lo incollo*): between backticks in the plain
   text, which the comment fields of this page paste as code, and as `<code>` in the rich copy,
   for the apps that read it. The icon is his file, viewBox and stroke as he drew them. */
const REF_ICON = [
  "M600,533.33c0,94.28,0,141.42-29.29,170.71-29.29,29.29-76.43,29.29-170.71,29.29h-100c-94.28,0-141.42,0-170.71-29.29-29.29-29.29-29.29-76.43-29.29-170.71v-166.67c0-94.28,0-141.42,29.29-170.71,29.29-29.29,76.43-29.29,170.71-29.29h100c94.28,0,141.42,0,170.71,29.29,29.29,29.29,29.29,76.43,29.29,170.71v166.67Z",
  "M200,166.67c0-55.23,44.77-100,100-100h133.33c125.71,0,188.56,0,227.61,39.05,39.05,39.05,39.05,101.91,39.05,227.61v200c0,55.23-44.77,100-100,100",
];
function refButton(id) {
  const ref = String(id || "").toLowerCase();
  const button = el("button", undefined, "card-ref");
  button.type = "button";
  button.title = "Copia il riferimento " + ref;
  button.setAttribute("aria-label", "Copia il riferimento " + ref);
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 800 800");
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", "50");
  svg.setAttribute("aria-hidden", "true");
  for (const d of REF_ICON) {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", d);
    svg.append(path);
  }
  button.append(svg);
  button.addEventListener("click", async () => {
    try {
      const safe = ref.replace(/[&<>"]/g, (c) => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]));
      await copyText("`" + ref + "`", "<code>" + safe + "</code>");
      toast("Riferimento copiato: " + ref);
      report("Riferimento copiato: " + ref);
    } catch {
      toast("Il browser non ha permesso la copia negli appunti.", true);
    }
  });
  return button;
}
for (const card of document.querySelectorAll(".card.test, .card.question, .label-card"))
  card.append(refButton(card.dataset.id));
window.feedbackRestoreLabel = (area) => {
  const card = area.closest(".label-card");
  const item = card && labelById(card.dataset.id);
  if (!item) return;
  if (!window.confirm("Vuoi tornare alla mia proposta originale?")) return;
  writeLabel(item, item.proposal);
  area.value = item.proposal;
  window.feedbackFormatting?.refresh();
  changed();
};
// File picker and drag-and-drop share validation and preserve the original bytes.
function imageInputs(card) {
  if (!card.classList.contains("extra")) return [card.querySelector(".images")].filter(Boolean);
  return Array.from(document.querySelectorAll("#altro-attach .images, #altro-overlay-attach .images"));
}
async function attachFiles(card, files) {
  const inputs = imageInputs(card);
  const input = inputs[0];
  if (!loaded || !input || inputs.some(item => item.disabled) || !files.length) return;
  const initialDraft = draft, initialEntry = attachmentEntry(card);
  inputs.forEach(item => { item.disabled = true; });
  try {
    const usedBefore = usedAttachmentBytes();
    if (usedBefore + files.reduce((sum, file) => sum + file.size, 0) > maxTotal ||
        initialEntry.images.length + files.length > 30)
      throw Error("Massimo 30 allegati per riquadro e 20 MB complessivi.");
    const additions = await Promise.all(files.map(async (file) => {
      let type = file.type;
      if (!type || type === "application/octet-stream") {
        if (/\.svg$/i.test(file.name)) type = "image/svg+xml";
        if (/\.zip$/i.test(file.name)) type = "application/zip";
      }
      if (type === "application/x-zip-compressed") type = "application/zip";
      if (!allowedMime.includes(type) || file.size < 1 || file.size > maxFile)
        throw Error("Usa PNG, JPG, WebP, GIF, SVG o ZIP fino a 8 MB ciascuno e 20 MB complessivi.");
      if (type === "image/svg+xml") {
        const document = new DOMParser().parseFromString(await file.text(), "image/svg+xml");
        if (document.querySelector("parsererror") || document.documentElement.localName !== "svg" ||
            document.documentElement.namespaceURI !== "http://www.w3.org/2000/svg")
          throw Error("Il file SVG non è valido.");
      }
      if (type === "application/zip") {
        const signature = new Uint8Array(await file.slice(0, 4).arrayBuffer());
        if (signature.length !== 4 || signature[0] !== 80 || signature[1] !== 75 ||
            ![[3, 4], [5, 6], [7, 8]].some(([a, b]) => signature[2] === a && signature[3] === b))
          throw Error("Il file ZIP non è riconosciuto.");
      }
      // A copy of the bytes: a picked File can stop being readable if it changes on disk.
      let bytes;
      try {
        bytes = await file.arrayBuffer();
      } catch {
        throw Error("Impossibile leggere il file.");
      }
      return {name: file.name, type, size: file.size, blob: new Blob([bytes], {type})};
    }));
    if (draft !== initialDraft || attachmentEntry(card) !== initialEntry)
      throw Error("Le risposte sono state sostituite: allega nuovamente i file.");
    const used = usedAttachmentBytes();
    if (used + additions.reduce((sum, image) => sum + image.size, 0) > maxTotal ||
        initialEntry.images.length + additions.length > 30)
      throw Error("Massimo 30 allegati per riquadro e 20 MB complessivi.");
    initialEntry.images.push(...additions);
    drawAttachments(card);
    changed();
    report("Allegati aggiunti interi.");
  } catch (error) {
    report(error.message, true);
  } finally {
    inputs.forEach(item => {
      item.disabled = false;
      item.value = "";
    });
  }
}
async function decodeClipboardImage(source) {
  if (typeof createImageBitmap === "function") {
    try {
      return await createImageBitmap(source);
    } catch {
      // The Image fallback handles clipboard formats unsupported by createImageBitmap.
    }
  }
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(source);
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(Error("Impossibile leggere l'immagine dagli appunti."));
    };
    image.src = url;
  });
}
async function clipboardImageAsPng(event) {
  const data = event.clipboardData;
  if (!data) return null;
  const item = Array.from(data.items || []).find(candidate =>
    candidate.kind === "file" && /^image\//i.test(candidate.type));
  const source = item?.getAsFile?.() ||
    Array.from(data.files || []).find(file => /^image\//i.test(file.type));
  if (!source) return null;
  const image = await decodeClipboardImage(source);
  const width = image.width || image.naturalWidth;
  const height = image.height || image.naturalHeight;
  if (!width || !height) throw Error("L'immagine dagli appunti non ha dimensioni valide.");
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) throw Error("Impossibile convertire l'immagine in PNG.");
  context.drawImage(image, 0, 0);
  image.close?.();
  const png = await new Promise(resolve => canvas.toBlob(resolve, "image/png"));
  if (!png) throw Error("Impossibile convertire l'immagine in PNG.");
  return new File([png], "clipboard.png", {type: "image/png", lastModified: Date.now()});
}
function attachmentCardForPaste(target) {
  const card = target.closest?.(".test, .extra");
  if (card) return card;
  if (target.id === "notes-mobile-editor" || target.id === "notes-mobile" ||
      target.closest?.("#altro-overlay"))
    return document.querySelector(".extra");
  return null;
}
window.feedbackPasteImage = (event, target) => {
  const card = attachmentCardForPaste(target);
  const data = event.clipboardData;
  const hasImage = data && (Array.from(data.items || []).some(item =>
    item.kind === "file" && /^image\//i.test(item.type)) ||
    Array.from(data.files || []).some(file => /^image\//i.test(file.type)));
  if (!card || !hasImage) return false;
  event.preventDefault();
  clipboardImageAsPng(event)
    .then(file => attachFiles(card, [file]))
    .catch(error => report(error.message, true));
  return true;
};
document.addEventListener("paste", event => {
  const target = event.target;
  if (target.closest?.(".rich-editor")) return;
  if (target.matches?.("textarea:not([readonly])"))
    window.feedbackPasteImage(event, target);
});
// Keep file drops outside a response from replacing the document in this tab.
for (const name of ["dragover", "drop"]) document.addEventListener(name, (event) => {
  if (Array.from(event.dataTransfer.types).includes("Files")) event.preventDefault();
});
for (const card of document.querySelectorAll(".test")) {
  for (const b of card.querySelectorAll(".outcome"))
    b.addEventListener("click", () => {
      const value = entry(card.dataset.id);
      value.status = value.status === b.dataset.status ? "" : b.dataset.status;
      for (const peer of card.querySelectorAll(".outcome"))
        peer.setAttribute(
          "aria-pressed",
          String(peer.dataset.status === value.status),
        );
      changed();
    });
  card.querySelector(".comment").addEventListener("input", (event) => {
    entry(card.dataset.id).comment = event.target.value;
    changed();
  });
}
// A question: one option at a time, a second tap clears it; `Rimando` is one more option.
for (const card of document.querySelectorAll(".question")) {
  for (const b of card.querySelectorAll(".choice"))
    b.addEventListener("click", () => {
      const value = decision(card.dataset.id);
      value.choice = value.choice === b.dataset.choice ? "" : b.dataset.choice;
      for (const peer of card.querySelectorAll(".choice"))
        peer.setAttribute("aria-pressed", String(peer.dataset.choice === value.choice));
      changed();
    });
  card.querySelector(".question-comment").addEventListener("input", (event) => {
    decision(card.dataset.id).comment = event.target.value;
    changed();
  });
}
for (const card of document.querySelectorAll(".test, .extra")) {
  const input = card.querySelector(".images");
  input.addEventListener("change", () => {
    attachFiles(card, Array.from(input.files));
  });
  let dragDepth = 0;
  card.addEventListener("dragenter", (event) => {
    if (!Array.from(event.dataTransfer.types).includes("Files")) return;
    event.preventDefault();
    dragDepth++;
    card.classList.add("drop-active");
  });
  card.addEventListener("dragover", (event) => {
    if (!Array.from(event.dataTransfer.types).includes("Files")) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
  });
  card.addEventListener("dragleave", () => {
    if (--dragDepth <= 0) {
      dragDepth = 0;
      card.classList.remove("drop-active");
    }
  });
  card.addEventListener("drop", (event) => {
    if (!Array.from(event.dataTransfer.types).includes("Files")) return;
    event.preventDefault();
    dragDepth = 0;
    card.classList.remove("drop-active");
    attachFiles(card, Array.from(event.dataTransfer.files));
  });
}
const altroOverlayImages = document.querySelector("#altro-overlay-attach .images");
if (altroOverlayImages) {
  altroOverlayImages.addEventListener("change", () => {
    const card = document.querySelector(".extra");
    if (card) attachFiles(card, Array.from(altroOverlayImages.files));
  });
}
/* The Mac is shown on the download row and changed in a modal (as in AIV, where the user asked:
   *inutile lasciarli sempre compilabili: non cambio dispositivi ad ogni giro*). The field writes
   the draft only on OK; Annulla, Escape and the scrim leave it as it was. */
const devicesDialog = document.querySelector("#devices-dialog");
function syncDevices() {
  document.querySelector("#device").value = draft.device;
  document.querySelector("#device-shown").textContent = draft.device.trim() || "non indicato";
}
document.querySelector("#devices-edit").addEventListener("click", () => {
  syncDevices();
  devicesDialog.showModal();
});
// On a phone the device row has its own edit icon (the user's mockup for AIV, 2026-10-06): the
// same dialog, with the caret already in the field.
for (const button of document.querySelectorAll(".device-edit")) {
  button.addEventListener("click", () => {
    syncDevices();
    devicesDialog.showModal();
    document.querySelector("#" + button.dataset.field).focus();
  });
}
document.querySelector("#devices-cancel").addEventListener("click", () => devicesDialog.close());
devicesDialog.addEventListener("click", (event) => {
  if (event.target === devicesDialog) devicesDialog.close();
});
document.querySelector("#devices-ok").addEventListener("click", (event) => {
  event.preventDefault();
  const value = document.querySelector("#device").value;
  const edited = value !== draft.device;
  draft.device = value;
  devicesDialog.close();
  if (edited) changed();
});
devicesDialog.addEventListener("close", syncDevices);

function syncInstalledConfirm() {
  const box = document.querySelector("#installed-confirm");
  if (box) box.checked = draft.installed === spec.version;
}
document.querySelector("#installed-confirm")?.addEventListener("change", (event) => {
  draft.installed = event.target.checked ? spec.version : "";
  changed();
});

let altroSyncing = false;
function syncAltroFields(source) {
  if (altroSyncing) return;
  altroSyncing = true;
  const value = draft.notes || "";
  for (const id of ["notes", "notes-mobile"]) {
    const node = document.querySelector("#" + id);
    if (!node || node === source) continue;
    if (node.value !== value) node.value = value;
  }
  // Keep rich-editor mirrors in sync when format.js has wrapped #notes.
  window.feedbackFormatting?.refresh?.();
  altroSyncing = false;
}
function onAltroInput(event) {
  draft.notes = event.target.value;
  syncAltroFields(event.target);
  changed();
}
for (const id of ["notes", "notes-mobile"]) {
  const node = document.querySelector("#" + id);
  if (node) node.addEventListener("input", onAltroInput);
}

// --- Mobile Altro overlay (long press on the floating ⇥); same draft.notes as the page Altro ---
const altroOverlay = document.querySelector("#altro-overlay");
/* The overlay is as tall as what the keyboard leaves visible (his note of 2026-10-10: with
   attachments he could not scroll down to them). The overlay opens with the caret in the field,
   so on Android the keyboard opens with it; it shrinks only the visual viewport, and a panel as
   tall as the whole screen kept its end under the keyboard: measured with four attachments, the
   panel scrolled 213px while they were some 700px down. Following visualViewport, the panel
   scrolls as far as its content goes; with nothing to scroll it still holds still. */
function fitAltroOverlay() {
  const view = window.visualViewport;
  if (!altroOverlay || altroOverlay.hidden || !view) return;
  altroOverlay.style.top = view.offsetTop + "px";
  altroOverlay.style.height = view.height + "px";
}
window.visualViewport?.addEventListener("resize", fitAltroOverlay);
window.visualViewport?.addEventListener("scroll", fitAltroOverlay);
function setAltroOverlayOpen(open) {
  if (!altroOverlay) return;
  altroOverlay.hidden = !open;
  document.body.classList.toggle("altro-overlay-open", open);
  altroOverlay.style.top = altroOverlay.style.height = "";
  fitAltroOverlay();
  if (open) {
    syncAltroFields();
    const editor =
      document.querySelector("#notes-mobile-editor") ||
      document.querySelector("#notes-mobile");
    editor?.focus?.();
  }
}
// The overlay has no header since 2026-10-06: its Chiudi key, in the row under the field, is
// made by feedback-format.js, which runs after this file.
window.feedbackCloseAltro = () => setAltroOverlayOpen(false);
altroOverlay?.addEventListener("click", (event) => {
  if (event.target === altroOverlay) setAltroOverlayOpen(false);
});

// --- Consegna commands: one row under Altro, copied into the mobile Altro overlay ---
// The page row keeps the ids (#save, #copy...); the copy is found through data-command.
const pageCommands = document.querySelector("#extra-section .altro-commands");
const overlayCommands = pageCommands.cloneNode(true);
for (const node of overlayCommands.querySelectorAll("[id]")) node.removeAttribute("id");
// Under the panel, not in its body: feedback-format.js rewraps the body around the field.
document.querySelector(".altro-overlay-panel").append(overlayCommands);

async function send() {
  draft.completed = new Date().toISOString();
  revision++;
  if (!await save()) {
    report("Invio non confermato: le ultime modifiche non sono ancora disponibili all'agente. Riprova quando il salvataggio cloud funziona.", true);
    toast("Invio non riuscito: riprova quando il salvataggio funziona.", true);
    return;
  }
  report(
    remote
      ? "Giro reso leggibile all'agente. Puoi modificarlo e inviarlo di nuovo; l'agente lo leggerà solo dopo il tuo via in chat."
      : "Risposte pronte. Per renderle leggibili dal cloud, esportale, importale nel documento cloud e premi Invia.",
  );
  toast(remote ? "Giro inviato." : "Risposte pronte: esportale per inviarle.");
}
// A save asked by hand answers with a toast, like Invia (the user's request, 2026-10-05): the
// state line changes too, but while one writes it is out of sight. Ctrl/Cmd+S, the Salva command
// and the floating key all come here; the saves the page makes by itself stay silent.
async function saveByHand() {
  if (await save()) toast(remote ? "Salvato nel cloud." : "Salvato in questo browser.");
  else toast("Salvataggio non riuscito: esporta le risposte prima di chiudere.", true);
}
// The export is a ZIP: feedback.json with the answers, and the attachments next to it with
// short names, the test's position on two digits plus a letter (01a.png, 01b.jpg, 02a.webp),
// and 00 for Altro (00a.png). feedback.json keeps each original name next to the short one.
// Answers to tests no longer on the page use their identifier (3.40-02a.png).
const extensions = { "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp",
  "image/gif": "gif", "image/svg+xml": "svg", "application/zip": "zip" };
function letters(index) {
  let name = "";
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26))
    name = String.fromCharCode(97 + ((n - 1) % 26)) + name;
  return name;
}
async function exportZip() {
  try {
    const files = [];
    const position = new Map(spec.items.map((item, index) => [item.id, String(index + 1).padStart(2, "0")]));
    const describe = (images, prefix) => images.map((file, index) => {
      const name = prefix + letters(index) + "." + extensions[file.type];
      files.push({ name, blob: file.blob });
      return { name: file.name, type: file.type, size: file.size, file: name };
    });
    const data = {
      ...draft,
      version: spec.version,
      entries: Object.fromEntries(Object.entries(draft.entries).map(([id, value]) =>
        [id, { ...value, images: describe(value.images, position.get(id) || id) }])),
      extra: { images: describe(draft.extra.images, "00") },
    };
    const json = new Blob([JSON.stringify(data, null, 2)], { type: "application/json" });
    const zip = await feedbackZip.write([{ name: "feedback.json", blob: json }, ...files]);
    const url = URL.createObjectURL(zip), a = el("a");
    a.href = url;
    a.download = `Aomidori-feedback-${spec.version}.zip`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    report("Esportato lo ZIP, con risposte e allegati.");
  } catch (error) {
    report("Esportazione non riuscita: " + error.message, true);
  }
}
// Import takes the ZIP of the export, or a JSON exported before 2026-10-03 with base64 inside.
async function importFile(input) {
  const file = input.files[0];
  if (!file) return;
  try {
    if (file.size > 35 * 1024 * 1024) throw Error("Il file supera 35 MB.");
    const head = new Uint8Array(await file.slice(0, 2).arrayBuffer());
    let raw;
    if (head[0] === 0x50 && head[1] === 0x4b) {
      const files = await feedbackZip.read(file);
      const json = files.get("feedback.json");
      if (!json) throw Error("Nello ZIP manca feedback.json.");
      raw = JSON.parse(new TextDecoder().decode(json));
      const attach = (images) => Array.isArray(images) ? images.map((img) => {
        if (!img || typeof img.file !== "string") return img;
        const bytes = files.get(img.file);
        if (!bytes) throw Error("Nello ZIP manca " + img.file + ".");
        const { file: _, ...rest } = img;
        return { ...rest, blob: new Blob([bytes], { type: String(img.type) }) };
      }) : images;
      for (const value of Object.values(raw?.entries || {})) if (value) value.images = attach(value.images);
      if (raw?.extra) raw.extra.images = attach(raw.extra.images);
    } else raw = JSON.parse(await file.text());
    draft = validate(raw);
    revision++;
    hydrate();
    await save();
    // An answer shows only inside its test's card: say how many have no card on this page,
    // or an import of a closed round looks like it did nothing.
    const listed = new Set(spec.items.map((item) => item.id));
    const answers = Object.keys(draft.entries), closed = answers.filter((id) => !listed.has(id)).length;
    report(!closed ? "Risposte importate e ripristinate."
      : closed === answers.length ? `Risposte importate (${answers.length}), tutte di prove chiuse: la pagina non le mostra.`
      : `Risposte importate (${answers.length}); ${closed} sono di prove chiuse e la pagina non le mostra.`);
  } catch (error) {
    report("Importazione annullata: " + error.message, true);
  } finally {
    input.value = "";
  }
}
async function reset() {
  if (
    !confirm(
      remote ? "Azzera la bozza cloud, rimuovendo risposte e allegati da tutti i dispositivi? Esporta le risposte per conservarli." : "Cancellare tutte le risposte e tutti gli allegati salvati in questo browser? Esporta le risposte per conservarle.",
    )
  )
    return;
  draft = blank();
  revision++;
  hydrate();
  await save();
  report(remote ? "Bozza cloud azzerata." : "Risposte del browser azzerate.");
}
const commands = { reset, copy, export: exportZip, save: saveByHand, send };
for (const row of [pageCommands, overlayCommands]) {
  for (const button of row.querySelectorAll("button[data-command]"))
    button.addEventListener("click", () => commands[button.dataset.command]());
  const picker = row.querySelector('[data-command="import"] input');
  picker.addEventListener("change", () => importFile(picker));
}
// The page's only keyboard handler: Ctrl/Cmd+S saves, Escape closes the Altro overlay,
// T switches the theme outside the fields, and Cmd+Up / Cmd+Down (Ctrl elsewhere) go to the
// top and the bottom of the page (the user's request, 2026-10-04). In a field those two keep
// moving the caret, which is what they do in any text. The format shortcuts belong to each
// editor.
function typing(target) {
  if (!(target instanceof Element)) return false;
  if (["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName)) return true;
  return Boolean(target.closest("[contenteditable]")?.isContentEditable);
}
document.addEventListener("keydown", (event) => {
  const modified = event.ctrlKey || event.metaKey || event.altKey || event.shiftKey;
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
    event.preventDefault();
    saveByHand();
  } else if (event.key === "Escape" && altroOverlay && !altroOverlay.hidden) {
    setAltroOverlayOpen(false);
  } else if ((event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey &&
      (event.key === "ArrowUp" || event.key === "ArrowDown") && !typing(event.target)) {
    event.preventDefault();
    window.scrollTo({ top: event.key === "ArrowUp" ? 0 : document.documentElement.scrollHeight });
  } else if (event.key.toLowerCase() === "t" && !modified && !typing(event.target)) {
    event.preventDefault();
    toggleTheme();
  }
});
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden" && saveTimer !== null) save();
});
function controls(disabled) {
  for (const control of document.querySelectorAll("button,input,textarea"))
    control.disabled = disabled;
  window.feedbackFormatting?.setDisabled(disabled);
}

// --- Desktop: a wheel over Altro never scrolls the page ---
// The user's request, 2026-10-06: with the pointer on Altro, the wheel and the touchpad move
// only Altro. overscroll-behavior stops the chain at the end of a scroll, but it does nothing
// where no box under the pointer can scroll, so there the event is stopped here.
(() => {
  const altro = document.querySelector("#extra-section");
  const wide = window.matchMedia("(min-width: 1100px)");
  if (!altro) return;
  const canScroll = (box, dy) =>
    box.scrollHeight > box.clientHeight + 1 &&
    /(auto|scroll)/.test(getComputedStyle(box).overflowY) &&
    (dy < 0 ? box.scrollTop > 0 : box.scrollTop + box.clientHeight < box.scrollHeight - 1);
  altro.addEventListener("wheel", (event) => {
    if (!wide.matches || event.deltaY === 0) return;
    for (let box = event.target; box && box !== altro.parentElement; box = box.parentElement)
      if (box instanceof Element && canScroll(box, event.deltaY)) return;
    event.preventDefault();
  }, { passive: false });
  // Altro scrolls only when there is something to scroll (the user's note, 2026-10-06, with a
  // screenshot: a bar almost as long as Altro, about 1% of overflow, appeared at a scroll
  // attempt). Altro is a flex column, so at its maximum height its children shrink first and it
  // overflows only past their minimum heights; on his Mac that left a few pixels, all of them
  // inside the empty bottom padding. Scrolling them would show nothing, so while the overflow
  // stays within the padding Altro does not scroll at all.
  // scrollHeight counts the content with overflow hidden too, so the class is never lifted to
  // measure: lifting it would change the layout inside the observer that called this.
  const fit = () => {
    const room = parseFloat(getComputedStyle(altro).paddingBottom) || 0;
    altro.classList.toggle("fits", wide.matches && altro.scrollHeight <= altro.clientHeight + room + 1);
  };
  const watch = new ResizeObserver(fit);
  watch.observe(altro);
  for (const child of altro.children) watch.observe(child);
  new MutationObserver(() => {
    for (const child of altro.children) watch.observe(child);
    fit();
  }).observe(altro, { childList: true, subtree: true });
  wide.addEventListener("change", fit);
  fit();
})();

// --- Desktop: at the end of the page Prossimi passi ends where Altro does ---
// Altro is sticky, so at the end of the page its bottom edge is its sticky top plus its height;
// the room under the grid is set so that the last card ends there too (the user's request,
// 2026-10-04). Only where the two columns exist; elsewhere the variable is removed.
(() => {
  const columns = document.querySelector(".feedback-columns");
  const altro = document.querySelector("#extra-section");
  const wide = window.matchMedia("(min-width: 1100px)");
  if (!columns || !altro) return;
  function align() {
    const last = columns.lastElementChild;
    if (!wide.matches || !last || last === altro) {
      columns.style.removeProperty("--df-tail");
      return;
    }
    columns.style.setProperty("--df-tail", "0px");
    const top = parseFloat(getComputedStyle(altro).top) || 0;
    const below = document.documentElement.scrollHeight - (last.getBoundingClientRect().bottom + window.scrollY);
    const wanted = window.innerHeight - (top + altro.offsetHeight);
    columns.style.setProperty("--df-tail", Math.max(0, Math.round(wanted - below)) + "px");
  }
  const observer = new ResizeObserver(align);
  observer.observe(altro);
  observer.observe(columns);
  window.addEventListener("resize", align);
  wide.addEventListener("change", align);
  align();
})();
