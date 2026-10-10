"use strict";
(() => {
  const editors = [];
  const iconPaths = {
    // Bold: the Arial Bold "B" the button used to set in text (22px, 0.6px stroke), as a
    // path in the 24px box, so it no longer depends on the fonts installed. Glyph from
    // Liberation Sans Bold, metric-compatible with Arial; its ink matched the text version.
    bold: "M18.945 14.182Q18.945 16.244 17.398 17.372Q15.851 18.5 13.101 18.5H5.528V3.364H12.457Q15.228 3.364 16.651 4.326Q18.075 5.287 18.075 7.167Q18.075 8.456 17.36 9.342Q16.646 10.229 15.185 10.54Q17.022 10.755 17.983 11.695Q18.945 12.635 18.945 14.182ZM14.884 7.597Q14.884 6.576 14.234 6.146Q13.584 5.717 12.306 5.717H8.697V9.466H12.328Q13.67 9.466 14.277 8.999Q14.884 8.531 14.884 7.597ZM15.765 13.935Q15.765 11.808 12.714 11.808H8.697V16.147H12.833Q14.358 16.147 15.062 15.594Q15.765 15.041 15.765 13.935Z",
    // Italic, link and code keep Material-style paths.
    italic: "M10 4v3h2.21l-3.42 10H6v3h8v-3h-2.21l3.42-10H18V4z",
    link: "M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7a5 5 0 0 0 0 10h4v-1.9H7A3.1 3.1 0 0 1 3.9 12zM8 13h8v-2H8v2zm9-6h-4v1.9h4a3.1 3.1 0 0 1 0 6.2h-4V17h4a5 5 0 0 0 0-10z",
    code: "M8.7 16.7 3.9 12l4.8-4.7L7.3 5.9 1.2 12l6.1 6.1 1.4-1.4zm6.6 0 1.4 1.4L22.8 12l-6.1-6.1-1.4 1.4 4.8 4.7-4.8 4.7z",
  };
  function resetIcon() {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    svg.setAttribute("fill", "none");
    svg.setAttribute("stroke", "currentColor");
    svg.setAttribute("stroke-width", "2");
    svg.setAttribute("stroke-linecap", "round");
    svg.setAttribute("stroke-linejoin", "round");
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    // Small circular arrow. Drawn here; not taken from an external reset file.
    path.setAttribute("d", "M20 12a8 8 0 1 1-2.2-5.5M20 4.5V9h-4.5");
    path.setAttribute("fill", "none");
    svg.append(path);
    return svg;
  }
  function formatIcon(kind) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", iconPaths[kind]);
    if (kind === "bold") {
      // A thin stroke of its own colour gives the letter the weight of the other glyphs.
      path.setAttribute("stroke", "currentColor");
      path.setAttribute("stroke-width", "0.6");
      path.setAttribute("paint-order", "stroke fill");
    }
    svg.append(path);
    return svg;
  }
  function node(tag, text, className) {
    const element = document.createElement(tag);
    if (text !== undefined) element.textContent = text;
    if (className) element.className = className;
    return element;
  }
  function strokeIcon(paths, width = 2) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    svg.setAttribute("fill", "none");
    svg.setAttribute("stroke", "currentColor");
    svg.setAttribute("stroke-width", String(width));
    svg.setAttribute("stroke-linecap", "round");
    svg.setAttribute("stroke-linejoin", "round");
    for (const d of paths) {
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d);
      svg.append(path);
    }
    return svg;
  }
  // Mobile Altro: two rows of six keys under the field, both always visible (the user's request,
  // 2026-10-06, which drops the two states of the mockup Altro_mobile and their switch keys):
  // Allega, the four formats and Chiudi, then the six commands. The commands are the copy
  // feedback-ui.js puts under the panel: it moves into these rows.
  function overlayRow(actions) {
    const close = node("button", undefined, "altro-row-key altro-row-close");
    close.type = "button";
    close.id = "altro-overlay-close";
    close.setAttribute("aria-label", "Chiudi");
    close.title = "Chiudi";
    close.append(strokeIcon(["M6 6l12 12", "M18 6 6 18"]));
    close.addEventListener("pointerdown", event => event.preventDefault());
    close.addEventListener("click", () => window.feedbackCloseAltro?.());
    actions.append(close);
    const commands = document.querySelector(".altro-overlay-panel > .altro-commands");
    if (commands) actions.append(commands);
  }
  function webAddress(value) {
    try {
      const address = new URL(value);
      return ["http:", "https:"].includes(address.protocol) ? address.href : null;
    } catch {
      return null;
    }
  }
  // Parse inline emphasis, code, and web links; user text never becomes HTML.
  function inline(text, parent, depth = 0) {
    if (depth > 12) {
      parent.append(document.createTextNode(text));
      return;
    }
    let plain = "";
    const flush = () => {
      if (plain) parent.append(document.createTextNode(plain));
      plain = "";
    };
    for (let index = 0; index < text.length;) {
      if (text[index] === "\\" && /[\\*`\[\]_]/.test(text[index + 1] || "")) {
        plain += text[index + 1];
        index += 2;
        continue;
      }
      if (text[index] === "`") {
        const close = text.indexOf("`", index + 1);
        if (close > index) {
          flush();
          parent.append(node("code", text.slice(index + 1, close)));
          index = close + 1;
          continue;
        }
      }
      const link = /^\[((?:\\.|[^\]\\])+)\]\((https?:\/\/[^\s)]+)\)/.exec(text.slice(index));
      const address = link && webAddress(link[2]);
      if (address) {
        flush();
        const anchor = node("a");
        anchor.href = address;
        anchor.target = "_blank";
        anchor.rel = "noopener noreferrer";
        inline(link[1].replace(/\\([\\*`\[\]_])/g, "$1"), anchor, depth + 1);
        parent.append(anchor);
        index += link[0].length;
        continue;
      }
      let matched = false;
      for (const marker of ["***", "**", "*", "_"]) {
        if (!text.startsWith(marker, index)) continue;
        let end = index + marker.length;
        while (end < text.length) {
          if (text[end] === "\\") { end += 2; continue; }
          if (text.startsWith(marker, end)) break;
          end++;
        }
        if (end >= text.length) continue;
        if (end <= index + marker.length) continue;
        flush();
        const emphasis = node(marker === "*" || marker === "_" ? "em" : "strong");
        if (marker === "***") {
          const italic = node("em");
          inline(text.slice(index + 3, end), italic, depth + 1);
          emphasis.append(italic);
        } else inline(text.slice(index + marker.length, end), emphasis, depth + 1);
        parent.append(emphasis);
        index = end + marker.length;
        matched = true;
        break;
      }
      if (!matched) plain += text[index++];
    }
    flush();
  }

  // Whether a node sets bold or italic itself: true, false, or undefined when it says nothing.
  // An inline style wins over the tag, as in markdown() (a pasted <b style="font-weight:normal">).
  const weightOf = up => up.style.fontWeight ? /^(bold|[6-9]00)$/.test(up.style.fontWeight) : ["B", "STRONG"].includes(up.tagName) || undefined;
  const slantOf = up => up.style.fontStyle ? up.style.fontStyle === "italic" : ["I", "EM"].includes(up.tagName) || undefined;
  /* Bold or italic on a piece of inline code, from inside it: true only when every letter of the
     code has it. Markdown has one style per code span, and ⌘B on the code's text puts the <b>
     inside the <code>, where markdown() used to read only the text (his note of 2026-10-10: code
     with bold did not survive the save). */
  function codeStyle(code, outer, test) {
    const texts = [];
    const walker = document.createTreeWalker(code, NodeFilter.SHOW_TEXT);
    for (let text; (text = walker.nextNode());) if (text.textContent) texts.push(text);
    if (!texts.length) return outer;
    return texts.every(text => {
      for (let up = text.parentElement; up; up = up.parentElement) {
        const said = test(up);
        if (said !== undefined) return said;
        if (up === code) break;
      }
      return outer;
    });
  }

  function markdown(root) {
    const runs = [];
    const add = (text, style) => {
      if (!text) return;
      const last = runs.at(-1);
      if (last && last.bold === style.bold && last.italic === style.italic && last.href === style.href && last.code === style.code) last.text += text;
      else runs.push({...style, text});
    };
    function visit(element, style) {
      if (element.nodeType === Node.TEXT_NODE) {
        add(element.textContent, style);
        return;
      }
      if (element.nodeType !== Node.ELEMENT_NODE) return;
      const tag = element.tagName;
      if (tag === "BR") {
        // Shift+Enter leaves a terminal BR to hold the caret on the new line.
        if (!element.nextSibling && element.previousSibling?.nodeName === "BR") return;
        add("\n", style);
        return;
      }
      const block = ["DIV", "P"].includes(tag);
      if (block && element.previousSibling) add("\n", {});
      // ⚠️ A run of its own, written back as it is: escaped with the rest, its backticks
      // became \` and the code came back as plain text (found by the check, 2026-10-04).
      // Bold and italic around it or inside it travel with it, as **`code`**.
      if (tag === "CODE") {
        add("`" + element.textContent + "`", {
          bold: codeStyle(element, Boolean(style.bold), weightOf),
          italic: codeStyle(element, Boolean(style.italic), slantOf),
          href: style.href,
          code: true
        });
        return;
      }
      const next = {
        bold: element.style.fontWeight ? /^(bold|[6-9]00)$/.test(element.style.fontWeight) : style.bold || ["B", "STRONG"].includes(tag),
        italic: element.style.fontStyle ? element.style.fontStyle === "italic" : style.italic || ["I", "EM"].includes(tag),
        href: tag === "A" ? webAddress(element.getAttribute("href")) : style.href
      };
      // An empty block's sole BR is a caret placeholder, not an extra line.
      if (!(block && element.childNodes.length === 1 && element.firstChild.nodeName === "BR")) {
        for (const child of element.childNodes) visit(child, next);
      }
    }
    // An empty field's sole BR is a caret placeholder. Empty text nodes do not count: one is
    // left after inline code to keep the caret out of it, and beside the BR it made a line.
    const filled = [...root.childNodes].filter((child) => !(child.nodeType === Node.TEXT_NODE && child.textContent === ""));
    if (!(filled.length === 1 && filled[0].nodeName === "BR")) {
      for (const child of root.childNodes) visit(child, {});
    }
    return runs.map(run => {
      let text = run.code ? run.text : run.text.replace(/[\\*`\[\]_]/g, "\\$&");
      const marker = (run.bold ? "**" : "") + (run.italic ? "*" : "");
      if (marker) text = text.replace(/^(\s*)([\s\S]*?\S)(\s*)$/, (_, before, body, after) => before + marker + body + marker + after);
      if (run.href) text = "[" + text + "](" + run.href.replace(/\(/g, "%28").replace(/\)/g, "%29") + ")";
      return text;
    }).join("");
  }
  // --- Undo and redo of the field's own (his request of 2026-10-10) ---
  /* Every style must be undone by ⌘Z, the way typing is. The browser's undo knows only what
     execCommand did: the code key builds its node by hand, so ⌘Z undid the typing before it and
     left the code in place. The field keeps its own history instead, as Markdown snapshots with
     the selection around each step, and ⌘Z, ⇧⌘Z, Ctrl+Y and the Edit menu walk it; the browser's
     own stack is never used. Typing of the same kind within GROUP_MS is one step, like the
     browser's. A change that comes from outside (cloud sync, import, a restored label) starts a
     new history: undoing past it would bring back a text the draft no longer has. */
  const GROUP_MS = 1200, HISTORY_CAP = 200;
  const BLOCKS = ["DIV", "P"];
  const fresh = md => ({stack: [{md, before: null, after: null, kind: null, at: 0}], index: 0});
  /* A point of the field as a count of characters, counted as markdown() counts lines: a text's
     letters, a BR, and the line a block starts. The nodes change when a step is undone; the
     count does not. */
  function countTo(box, stopNode, stopOffset) {
    let count = 0;
    const walk = node => {
      if (node.nodeType === Node.TEXT_NODE) {
        if (node === stopNode) { count += stopOffset; return true; }
        count += node.length;
        return false;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return false;
      if (node !== box && BLOCKS.includes(node.tagName) && node.previousSibling) count++;
      if (node.tagName === "BR") { count++; return node === stopNode; }
      for (let index = 0; index < node.childNodes.length; index++) {
        if (node === stopNode && index === stopOffset) return true;
        if (walk(node.childNodes[index])) return true;
      }
      return node === stopNode;
    };
    walk(box);
    return count;
  }
  function pointAt(box, target) {
    let count = 0, found = null;
    const before = node => { found = [node.parentNode, Array.prototype.indexOf.call(node.parentNode.childNodes, node)]; return true; };
    const walk = node => {
      if (node.nodeType === Node.TEXT_NODE) {
        if (count + node.length >= target) { found = [node, target - count]; return true; }
        count += node.length;
        return false;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return false;
      if (node !== box && (node.tagName === "BR" || BLOCKS.includes(node.tagName) && node.previousSibling)) {
        if (count >= target) return before(node);
        count++;
        if (node.tagName === "BR") return false;
      }
      for (const child of node.childNodes) if (walk(child)) return true;
      return false;
    };
    return walk(box) ? found : [box, box.childNodes.length];
  }
  function selectionOf(editor) {
    const selected = window.getSelection();
    if (!selected.rangeCount || !inside(editor, selected.getRangeAt(0))) return null;
    const range = selected.getRangeAt(0);
    return {start: countTo(editor.box, range.startContainer, range.startOffset), end: countTo(editor.box, range.endContainer, range.endOffset)};
  }
  function place(editor, chosen) {
    if (!chosen) return;
    const range = document.createRange();
    range.setStart(...pointAt(editor.box, chosen.start));
    range.setEnd(...pointAt(editor.box, chosen.end));
    const selected = window.getSelection();
    selected.removeAllRanges();
    selected.addRange(range);
    editor.range = range.cloneRange();
  }
  function remember(editor, kind) {
    const history = editor.history, md = editor.area.value, after = selectionOf(editor);
    const top = history.stack[history.index];
    const before = editor.before ?? after;
    editor.before = null;
    if (md === top.md) { top.after = after; return; }
    const now = Date.now();
    const typing = kind === "insertText" || /^delete(Content|Word)/.test(kind || "");
    if (typing && top.kind === kind && now - top.at < GROUP_MS && history.index > 0 && history.index === history.stack.length - 1) {
      Object.assign(top, {md, after, at: now});
      return;
    }
    history.stack.splice(history.index + 1);
    history.stack.push({md, before, after, kind, at: now});
    if (history.stack.length > HISTORY_CAP) history.stack.shift();
    history.index = history.stack.length - 1;
  }
  function rebuild(editor, md) {
    editor.area.value = md;
    editor.box.replaceChildren();
    inline(md, editor.box);
    editor.lastMarkdown = md;
    editor.range = null;
  }
  // One step back (-1) or forward (+1): the text of that step, and the selection around it.
  function travel(editor, step) {
    const history = editor.history, target = history.index + step;
    if (editor.area.disabled || target < 0 || target >= history.stack.length) return;
    const moved = history.stack[step < 0 ? history.index : target];
    history.index = target;
    rebuild(editor, history.stack[target].md);
    place(editor, step < 0 ? moved.before : moved.after);
    editor.area.dispatchEvent(new Event("input", {bubbles: true}));
    refreshNavigation();
  }
  function render(editor) {
    if (editor.area.value === editor.lastMarkdown) return;
    rebuild(editor, editor.area.value);
    editor.history = fresh(editor.area.value);
  }

  // --- Copy, cut and paste keep the styles (his request of 2026-10-10) ---
  /* A copy from a field carries its Markdown twice: as a type of its own, and as an attribute of
     the HTML copy, which survives browsers that drop unknown types. A paste that finds either
     puts the styles back; anything else, from another page or app, still goes in as plain text
     (no foreign HTML is ever read for its markup). Other apps get the plain text and the
     formatted HTML. */
  const MARKDOWN_TYPE = "application/x-aomidori-markdown";
  // The selection as Markdown, with the styles of the nodes around it, not only those inside.
  function selectedMarkdown(editor, range) {
    let piece = range.cloneContents();
    for (let up = range.commonAncestorContainer; up && up !== editor.box; up = up.parentNode) {
      if (up.nodeType !== Node.ELEMENT_NODE) continue;
      const shell = up.cloneNode(false);
      shell.append(piece);
      piece = shell;
    }
    const holder = document.createElement("div");
    holder.append(piece);
    return markdown(holder);
  }
  function toClipboard(data, md) {
    const shown = document.createElement("span");
    inline(md, shown);
    data.setData("text/plain", shown.textContent);
    shown.dataset.aomidoriMarkdown = md;
    data.setData("text/html", shown.outerHTML);
    data.setData(MARKDOWN_TYPE, md);
  }
  function fromClipboard(data) {
    const own = data.getData(MARKDOWN_TYPE);
    if (own) return own;
    const html = data.getData("text/html");
    if (!html.includes("data-aomidori-markdown")) return null;
    // An inert document: nothing in it runs or loads, and only the attribute is read.
    const marked = new DOMParser().parseFromString(html, "text/html").querySelector("[data-aomidori-markdown]");
    return marked ? marked.getAttribute("data-aomidori-markdown") : null;
  }
  // Puts nodes at the selection, the caret after them in a text of its own, so what follows is
  // plain: the way the code key and the attachment names have always done it.
  function insertNodes(editor, nodes) {
    const range = selection(editor);
    range.deleteContents();
    const piece = document.createDocumentFragment();
    piece.append(...nodes);
    const after = document.createTextNode("");
    piece.append(after);
    range.insertNode(piece);
    const caret = document.createRange();
    caret.setStart(after, 0);
    caret.collapse(true);
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(caret);
  }
  function insertMarkdown(editor, md) {
    const piece = document.createDocumentFragment();
    inline(md, piece);
    insertNodes(editor, [...piece.childNodes]);
  }
  function inside(editor, range) {
    return editor.box.contains(range.startContainer) && editor.box.contains(range.endContainer);
  }
  function selection(editor) {
    const selected = window.getSelection();
    if (selected.rangeCount && inside(editor, selected.getRangeAt(0))) return selected.getRangeAt(0);
    if (editor.range && inside(editor, editor.range)) {
      selected.removeAllRanges();
      selected.addRange(editor.range);
      return editor.range;
    }
    const range = document.createRange();
    range.selectNodeContents(editor.box);
    range.collapse(false);
    selected.removeAllRanges();
    selected.addRange(range);
    return range;
  }
  function sync(editor, kind) {
    // The original textarea remains the bridge to persistence and schema-1 exports.
    editor.area.value = markdown(editor.box);
    editor.lastMarkdown = editor.area.value;
    remember(editor, kind);
    editor.area.dispatchEvent(new Event("input", {bubbles: true}));
    refreshNavigation();
  }
  function links(editor) {
    for (const anchor of editor.box.querySelectorAll("a")) {
      anchor.target = "_blank";
      anchor.rel = "noopener noreferrer";
    }
  }
  function edit(editor, kind) {
    if (editor.area.disabled) return;
    editor.box.focus({preventScroll: true});
    const range = selection(editor);
    editor.before = selectionOf(editor);
    if (kind === "link") {
      const selected = range.toString();
      const container = range.startContainer.nodeType === Node.ELEMENT_NODE ? range.startContainer : range.startContainer.parentElement;
      const anchor = container.closest("a");
      const proposed = prompt("Indirizzo del link (http:// o https://):", anchor?.href || webAddress(selected) || "https://");
      if (proposed === null) return;
      const address = webAddress(proposed.trim());
      if (!address) {
        report("Inserisci un indirizzo http:// o https:// valido.", true);
        return;
      }
      if (range.collapsed && !anchor) {
        document.execCommand("insertText", false, "testo del link");
        const caret = window.getSelection().getRangeAt(0);
        const label = document.createRange();
        label.setStart(caret.endContainer, caret.endOffset - "testo del link".length);
        label.setEnd(caret.endContainer, caret.endOffset);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(label);
      }
      document.execCommand("createLink", false, address);
      links(editor);
    } else if (kind === "code") {
      // Rendered in the editor like bold, italic and links (the user's request, 2026-10-04):
      // a <code> node, which markdown() writes back between backticks. Inside one, the key
      // takes the code away again.
      const container = range.startContainer.nodeType === Node.ELEMENT_NODE ? range.startContainer : range.startContainer.parentElement;
      const current = container.closest("code");
      if (current && editor.box.contains(current)) {
        current.replaceWith(document.createTextNode(current.textContent));
      } else {
        // The selection's bold and italic go on the new code: replacing the text emptied its <b>.
        let made = node("code", range.toString() || "codice");
        for (const [command, tag] of [["italic", "em"], ["bold", "strong"]]) {
          if (!document.queryCommandState(command)) continue;
          const wrap = node(tag);
          wrap.append(made);
          made = wrap;
        }
        insertNodes(editor, [made]);
      }
    } else document.execCommand(kind === "bold" ? "bold" : "italic", false);
    sync(editor, "format");
  }
  for (const [index, area] of Array.from(document.querySelectorAll("textarea:not([readonly])")).entries()) {
    const label = area.parentElement;
    const wrapper = node("div", undefined, "formatted-field");
    label.replaceWith(wrapper);
    wrapper.append(label);
    area.id ||= "formatted-comment-" + index;
    label.id = area.id + "-label";
    const actions = node("div", undefined, "format-actions");
    const toolbar = node("div", undefined, "format-toolbar");
    toolbar.setAttribute("role", "group");
    toolbar.setAttribute("aria-label", "Formattazione del testo");
    const box = node("div", undefined, "rich-editor");
    box.id = area.id + "-editor";
    box.contentEditable = String(!area.disabled);
    box.setAttribute("role", "textbox");
    box.setAttribute("aria-multiline", "true");
    const named = area.getAttribute("aria-label");
    if (named) box.setAttribute("aria-label", named);
    else box.setAttribute("aria-labelledby", label.id);
    box.setAttribute("aria-disabled", String(area.disabled));
    box.dataset.placeholder = area.placeholder;
    box.spellcheck = true;
    label.htmlFor = box.id;
    label.addEventListener("click", () => box.focus());
    area.hidden = true;
    area.setAttribute("aria-hidden", "true");
    area.tabIndex = -1;
    if (area.classList.contains("label-revision")) {
      const reset = node("button");
      reset.type = "button";
      reset.className = "label-reset";
      reset.setAttribute("aria-label", "Ripristina la proposta originale");
      reset.append(resetIcon());
      reset.addEventListener("pointerdown", event => event.preventDefault());
      reset.addEventListener("click", () => window.feedbackRestoreLabel?.(area));
      actions.append(reset);
    }
    actions.append(toolbar);
    wrapper.append(area, box, actions);
    const editor = {area, box, range: null, lastMarkdown: null, history: fresh(area.value), before: null};
    editors.push(editor);
    for (const [kind, title, key] of [["bold", "Grassetto", "B"], ["italic", "Corsivo", "I"], ["code", "Codice", "M"], ["link", "Link", "K"]]) {
      const button = node("button");
      button.setAttribute("aria-label", title);
      button.append(formatIcon(kind));
      button.type = "button";
      button.dataset.format = kind;
      button.title = title + " (⌘" + key + " / Ctrl+" + key + ")";
      button.setAttribute("aria-keyshortcuts", "Meta+" + key + " Control+" + key);
      button.disabled = area.disabled;
      // Preserve the selection on both mouse and touch before the toolbar takes focus.
      button.addEventListener("pointerdown", event => event.preventDefault());
      button.addEventListener("click", () => edit(editor, kind));
      toolbar.append(button);
    }
    // Altro only: compact attach sits immediately left of this field's format toolbar.
    if (area.id === "notes" || area.id === "notes-mobile") {
      const attach = document.getElementById(area.id === "notes" ? "altro-attach" : "altro-overlay-attach");
      if (attach) {
        const cluster = node("div", undefined, "altro-format-cluster altro-halves");
        toolbar.replaceWith(cluster);
        cluster.append(attach, toolbar);
      }
      if (area.id === "notes-mobile") overlayRow(actions);
    } else {
      // Proof cards: label.attachment follows this field (or sits on the card).
      // Not #altro-attach, and not label cards (they have no such label).
      const sibling = wrapper.nextElementSibling;
      const card = wrapper.closest("article.test");
      const onCard = card ? card.querySelector(":scope > label.attachment") : null;
      const attach = sibling && sibling.matches("label.attachment") ? sibling : onCard;
      if (attach && attach.id !== "altro-attach" && !attach.classList.contains("altro-attach")) {
        const cluster = node("div", undefined, "altro-format-cluster");
        toolbar.replaceWith(cluster);
        cluster.append(attach, toolbar);
      }
    }
    box.addEventListener("beforeinput", event => {
      // Undo and redo from the Edit menu or a phone's keyboard walk the field's own history.
      if (event.inputType === "historyUndo" || event.inputType === "historyRedo") {
        event.preventDefault();
        travel(editor, event.inputType === "historyUndo" ? -1 : 1);
        return;
      }
      // The selection before a change: where ⌘Z puts it back. Kept from the first of a group.
      editor.before ??= selectionOf(editor);
      // Both Enter variants use blocks, avoiding a browser-only terminal newline placeholder.
      if (event.inputType === "insertLineBreak") {
        event.preventDefault();
        document.execCommand("insertParagraph", false);
      }
    });
    box.addEventListener("input", event => { links(editor); sync(editor, event.inputType); });
    box.addEventListener("paste", event => {
      if (window.feedbackPasteImage?.(event, box)) return;
      event.preventDefault();
      editor.before = selectionOf(editor);
      const own = fromClipboard(event.clipboardData);
      if (own !== null) {
        insertMarkdown(editor, own);
        sync(editor, "insertFromPaste");
        return;
      }
      // Plain-text paste prevents foreign HTML, styles and active elements entering the editor.
      const text = event.clipboardData.getData("text/plain");
      /* A text that is all between backticks goes in as inline code, as the Codice key makes it
         (his request of 2026-10-09: the reference a card's copy mark copies appears as code
         when pasted). Anything else stays plain. */
      const code = /^`([^`\n]+)`$/.exec(text.trim());
      if (code) {
        insertNodes(editor, [node("code", code[1])]);
        sync(editor, "insertFromPaste");
        return;
      }
      document.execCommand("insertText", false, text);
    });
    for (const name of ["copy", "cut"]) {
      box.addEventListener(name, event => {
        const range = selection(editor);
        if (range.collapsed) return;
        event.preventDefault();
        toClipboard(event.clipboardData, selectedMarkdown(editor, range));
        if (name === "cut" && !editor.area.disabled) {
          editor.before = selectionOf(editor);
          range.deleteContents();
          sync(editor, "deleteByCut");
        }
      });
    }
    box.addEventListener("drop", event => {
      // File drops continue to the card's existing attachment handler.
      if (event.dataTransfer.files.length) event.preventDefault();
      else {
        event.preventDefault();
        box.focus();
        document.execCommand("insertText", false, event.dataTransfer.getData("text/plain"));
      }
    });
    box.addEventListener("click", event => {
      const anchor = event.target.closest("a");
      if (anchor && webAddress(anchor.href)) {
        event.preventDefault();
        window.open(anchor.href, "_blank", "noopener,noreferrer");
      }
    });
    box.addEventListener("keydown", event => {
      const key = event.key.toLowerCase();
      if ((event.metaKey || event.ctrlKey) && !event.altKey && (key === "z" || key === "y" && !event.shiftKey)) {
        event.preventDefault();
        travel(editor, key === "y" || event.shiftKey ? 1 : -1);
        return;
      }
      const kind = {b: "bold", i: "italic", m: "code", k: "link"}[key];
      if (kind && (event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey) {
        event.preventDefault();
        edit(editor, kind);
      }
    });
    area.addEventListener("input", () => render(editor));
    render(editor);
  }
  document.addEventListener("selectionchange", () => {
    const selected = window.getSelection();
    if (!selected.rangeCount) return;
    const range = selected.getRangeAt(0);
    for (const editor of editors) {
      if (!inside(editor, range)) continue;
      editor.range = range.cloneRange();
      for (const kind of ["bold", "italic"]) {
        editor.box.parentElement.querySelector('[data-format="' + kind + '"]').setAttribute("aria-pressed", String(document.queryCommandState(kind)));
      }
    }
  });
  // The editor being written in: the one that has the focus, and only if it can be edited.
  function writing() {
    return editors.find(editor => editor.box === document.activeElement && !editor.area.disabled) || null;
  }
  window.feedbackFormatting = {
    refresh: () => editors.forEach(render),
    // Whether a field is being written in now: an attachment click then writes its name there.
    writing: () => Boolean(writing()),
    /* Inserts text at the caret as inline code, rendered as the Codice key renders it (the
       user's request, 2026-10-06: an attachment's name goes in as code, not between quotes).
       The caret goes after the code, so what is typed next is plain. False when no field has
       the focus. */
    insertCodeAtCaret: text => {
      const editor = writing();
      if (!editor) return false;
      editor.before = selectionOf(editor);
      insertNodes(editor, [node("code", text)]);
      sync(editor, "format");
      return true;
    },
    setDisabled: disabled => editors.forEach(editor => {
      editor.box.contentEditable = String(!disabled);
      editor.box.setAttribute("aria-disabled", String(disabled));
    })
  };
})();
