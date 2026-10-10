"use strict";
/* Feedback document, start. Last of the four page scripts (see feedback-data.js): every
   function is defined by now. Locks the controls, loads the draft (cloud or browser),
   then unlocks them and keeps the cloud draft in step with other devices. */
controls(true);
let restoredCopy = false;
(async () => {
  try {
    if (remote) {
      const existing = await remote.load(validate);
      if (existing) draft = existing;
      remoteReady = true;
      remote.account(true);
      saved.textContent = existing ? "Risposte ripristinate dal cloud." : "Nessuna risposta nel cloud: puoi iniziare.";
      // The browser's copy that never reached the cloud, if newer than the cloud's (R2).
      const copy = await readBackup();
      if (copy && !copy.arrived && copy.draft?.version === spec.version &&
          Date.parse(copy.at) > Date.parse(existing?.updated ?? 0)) {
        const when = new Date(copy.at).toLocaleString("it-IT");
        if (window.confirm("In questo browser ci sono risposte del " + when + " che non sono arrivate al cloud. Le ripristino?")) {
          draft = validate(copy.draft);
          restoredCopy = true;
          saved.textContent = "Risposte ripristinate da questo browser: le salvo nel cloud.";
        } else {
          await writeBackup({ ...copy, arrived: true });
        }
      }
    } else {
      db = await new Promise((resolve, reject) => {
        const request = indexedDB.open("aomidori-feedback", 1);
        request.onupgradeneeded = () =>
          request.result.createObjectStore("drafts");
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
        request.onblocked = () =>
          reject(Error("Chiudi le altre schede del documento."));
      });
      db.onversionchange = () => {
        db.close();
        db = null;
        saved.textContent = "Memoria chiusa da un'altra scheda: esporta le risposte.";
      };
      const existing = await new Promise((resolve, reject) => {
        const request = db
          .transaction("drafts")
          .objectStore("drafts")
          .get("current");
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
      });
      if (existing) draft = validate(existing);
      saved.textContent = draft.updated
        ? "Risposte ripristinate dal browser."
        : "Nessuna risposta salvata: puoi iniziare.";
    }
  } catch (error) {
    remote?.failed(error);
    const needsLogin = remote && error.status === 401;
    saved.textContent = needsLogin
      ? "Accedi con GitHub per compilare il documento e importare le risposte."
      : (remote ? "Cloud non disponibile. " : "Memoria non disponibile o dati non leggibili. Esporta le risposte prima di chiudere. ") + error.message;
    saved.classList.toggle("error", !needsLogin);
  } finally {
    loaded = remote ? remoteReady : true;
    alignDocumentVersion();
    hydrate();
    controls(!loaded);
    refreshNavigation();
    // A restored copy goes to the cloud at once, as any other edit would.
    if (restoredCopy) {
      revision++;
      save();
    }
  }
})();

window.feedbackHasUnsaved = () => revision !== persistedRevision;
window.feedbackSaveForLogout = async () => {
  const done = await save() && revision === persistedRevision;
  if (done) await dropBackup();
  return done;
};
async function refreshRemote() {
  if (!remote || !remoteReady || syncing || pendingSaves || revision !== persistedRevision || document.hidden) return;
  const observed = revision;
  syncing = true;
  let locked = false;
  try {
    if (!await remote.hasUpdates() || observed !== revision || pendingSaves) return;
    controls(true);
    locked = true;
    const existing = await remote.load(validate);
    draft = existing || blank();
    alignDocumentVersion();
    revision++;
    persistedRevision = revision;
    hydrate();
    saved.textContent = "Risposte aggiornate dal cloud.";
    saved.classList.remove("error");
  } catch (error) {
    remote.failed(error);
    saved.textContent = "Sincronizzazione non riuscita. " + error.message;
    saved.classList.add("error");
  } finally {
    if (locked) { controls(false); refreshNavigation(); }
    syncing = false;
  }
}
if (remote) {
  setInterval(refreshRemote,15000);
  window.addEventListener("focus",refreshRemote);
  window.addEventListener("online",() => {
    if (remoteReady && revision !== persistedRevision && !pendingSaves) save();
    else refreshRemote();
  });
  document.addEventListener("visibilitychange",() => { if (!document.hidden) refreshRemote(); });
  window.addEventListener("beforeunload",event => {
    if (revision !== persistedRevision) { event.preventDefault(); event.returnValue = ""; }
  });
}
