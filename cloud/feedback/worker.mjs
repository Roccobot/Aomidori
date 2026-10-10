// Private single-owner feedback storage; GitHub OAuth requests only the public profile.
import {SupabaseStore} from './supabase-store.mjs';
const MAX_FILE = 8 * 1024 * 1024, MAX_TOTAL = 20 * 1024 * 1024;
const SESSION = '__Host-aomidori-session', STATE = '__Host-aomidori-state';
const json = (body, status = 200, extra = {}) => new Response(JSON.stringify(body), {status, headers: {'Content-Type':'application/json', 'Cache-Control':'no-store', ...extra}});
const cookie = (name, value, age) => `${name}=${value}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${age}`;
const encoder = new TextEncoder();
const b64 = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const un64 = text => Uint8Array.from(atob(text.replace(/-/g,'+').replace(/_/g,'/')), c => c.charCodeAt(0));
const cookies = request => Object.fromEntries((request.headers.get('Cookie') || '').split(';').map(part => part.trim().split('=')));
async function key(env) {
  return crypto.subtle.importKey('raw',encoder.encode(env.SESSION_SECRET),{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);
}
async function sign(env, data) {
  const body = b64(encoder.encode(JSON.stringify(data)));
  return body + '.' + b64(new Uint8Array(await crypto.subtle.sign('HMAC',await key(env),encoder.encode(body))));
}
async function verified(env, value) {
  try {
    const [body, signature, extra] = (value || '').split('.');
    if (extra || !body || !signature || !await crypto.subtle.verify('HMAC',await key(env),un64(signature),encoder.encode(body))) return null;
    const data = JSON.parse(new TextDecoder().decode(un64(body)));
    return data.exp > Date.now()/1000 ? data : null;
  } catch { return null; }
}
async function sessionData(request, env) {
  const data = await verified(env,cookies(request)[SESSION]);
  return data?.kind === 'session' && String(data.owner) === String(env.OWNER_ID) ? data : null;
}
async function authorized(request, env) {
  return Boolean(await sessionData(request,env));
}
/*
 * The session renews itself while it is used, since 2026-10-06 (the owner's draft was lost the
 * day a seven-day session expired in the middle of a round). A request at least a day after the
 * last renewal gets a fresh week; past the cap from the GitHub login the owner signs in again.
 */
const SESSION_DAYS = 7, RENEW_AFTER = 86400, SESSION_CAP = 60*86400;
async function renewal(request, env) {
  try {
    const session = await sessionData(request,env);
    if (!session) return null;
    const now = Date.now()/1000, since = session.since ?? now;
    if (session.exp - now > SESSION_DAYS*86400 - RENEW_AFTER || now - since > SESSION_CAP) return null;
    return cookie(SESSION,await sign(env,{...session,since,exp:now+SESSION_DAYS*86400}),SESSION_DAYS*86400);
  } catch { return null; }
}
const root = env => `feedback/v1/${env.OWNER_ID}/`;
const redirect = (location, setCookie) => new Response(null,{status:302,headers:{Location:location,'Set-Cookie':setCookie,'Cache-Control':'no-store'}});
function storageKey(value) { return typeof value === 'string' && /^[a-f0-9]{64}$/.test(value); }
function draftFiles(draft) {
  return [...Object.values(draft.entries || {}),draft.extra || {images:[]}].flatMap(entry => entry.images || []);
}
function validDraft(draft) {
  if (!draft || draft.schema !== 1 || draft.project !== 'Aomidori' || typeof draft.version !== 'string' || !draft.entries || !draft.decisions || !draft.extra) return false;
  if (Array.isArray(draft.entries) || Array.isArray(draft.decisions)) return false;
  for (const field of ['version','installed','device','notes']) if (typeof draft[field] !== 'string' || draft[field].length > 100000) return false;
  for (const entry of Object.values(draft.entries)) {
    if (!entry || !['','Tutto OK','Accettabile','Non approvato'].includes(entry.status) || typeof entry.comment !== 'string' || entry.comment.length > 100000 || !Array.isArray(entry.images) || entry.images.length > 30) return false;
  }
  for (const entry of Object.values(draft.decisions)) if (!entry || typeof entry.choice !== 'string' || typeof entry.comment !== 'string' || entry.comment.length > 100000) return false;
  if (draft.labels !== undefined) {
    if (!draft.labels || typeof draft.labels !== 'object' || Array.isArray(draft.labels) || Object.keys(draft.labels).length > 200) return false;
    for (const [id, entry] of Object.entries(draft.labels)) {
      if (!/^e-[A-Za-z0-9._-]+$/.test(id) || !entry || typeof entry.revision !== 'string' || entry.revision.length > 100000) return false;
    }
  }
  if (!Array.isArray(draft.extra.images) || draft.extra.images.length > 30) return false;
  const files = draftFiles(draft);
  return files.every(file => file && storageKey(file.storageKey) && typeof file.name === 'string' && file.name.length <= 1000 && ['image/png','image/jpeg','image/webp','image/gif','image/svg+xml','application/zip'].includes(file.type) && Number.isInteger(file.size) && file.size > 0 && file.size <= MAX_FILE && !('data' in file)) && files.reduce((sum,file) => sum+file.size,0) <= MAX_TOTAL;
}
async function handle(request, env) {
  const url = new URL(request.url), path = url.pathname;
  const ready = env.SESSION_SECRET && env.GITHUB_CLIENT_ID && env.GITHUB_CLIENT_SECRET && env.OWNER_ID
    && (env.FEEDBACK || env.SUPABASE_URL && env.SUPABASE_SECRET_KEY);
  if (path === '/feedback-cloud-config.js') return new Response('window.feedbackCloudConfig = '+JSON.stringify({endpoint:'/api/feedback',files:'/api/files/',login:'/auth/login',logout:'/auth/logout',account:'/auth/me'})+';', {headers:{'Content-Type':'application/javascript','Cache-Control':'no-store'}});
  if (!path.startsWith('/auth/') && !path.startsWith('/api/')) return env.ASSETS.fetch(request);
  if (!ready) return json({error:'Servizio cloud non configurato.'},503);
  const store = env.FEEDBACK || new SupabaseStore(env);
  if (path === '/auth/login' && request.method === 'GET') {
    const state = await sign(env,{kind:'state',nonce:crypto.randomUUID(),exp:Date.now()/1000+600});
    const destination = new URL('https://github.com/login/oauth/authorize');
    destination.search = new URLSearchParams({client_id:env.GITHUB_CLIENT_ID,redirect_uri:url.origin+'/auth/callback',state});
    return redirect(destination.href,cookie(STATE,state,600));
  }
  if (path === '/auth/callback' && request.method === 'GET') {
    const state = url.searchParams.get('state'), signed = await verified(env,state);
    if (!state || state !== cookies(request)[STATE] || signed?.kind !== 'state' || !url.searchParams.get('code')) return json({error:'Accesso scaduto o non valido. Riprova.'},400);
    const tokenResponse = await fetch('https://github.com/login/oauth/access_token',{method:'POST',headers:{Accept:'application/json','Content-Type':'application/json'},body:JSON.stringify({client_id:env.GITHUB_CLIENT_ID,client_secret:env.GITHUB_CLIENT_SECRET,code:url.searchParams.get('code'),redirect_uri:url.origin+'/auth/callback'})});
    if (!tokenResponse.ok) return json({error:'Accesso GitHub non disponibile.'},502);
    const token = await tokenResponse.json();
    if (!token.access_token) return json({error:'Accesso GitHub non riuscito.'},401);
    const profileResponse = await fetch('https://api.github.com/user',{headers:{Authorization:'Bearer '+token.access_token,'User-Agent':'Aomidori-feedback',Accept:'application/vnd.github+json'}});
    if (!profileResponse.ok) return json({error:'Identità GitHub non verificabile.'},502);
    const profile = await profileResponse.json();
    if (String(profile.id) !== String(env.OWNER_ID)) return json({error:'Questo documento è riservato al proprietario.'},403);
    if (typeof profile.login !== 'string' || !/^[A-Za-z0-9-]{1,39}$/.test(profile.login)) return json({error:'Nome utente GitHub non verificabile.'},502);
    const session = await sign(env,{kind:'session',owner:profile.id,username:profile.login,since:Date.now()/1000,exp:Date.now()/1000+SESSION_DAYS*86400});
    const response = redirect('/feedback',cookie(SESSION,session,SESSION_DAYS*86400));
    response.headers.append('Set-Cookie',cookie(STATE,'',0));
    return response;
  }
  if (path === '/auth/me' && request.method === 'GET') {
    const session = await sessionData(request,env);
    return json({authenticated:Boolean(session),username:session?.username || null});
  }
  if (!await authorized(request,env)) return json({error:'Accedi con GitHub per usare il salvataggio cloud.'},401);
  if (!['GET','HEAD'].includes(request.method) && request.headers.get('Origin') !== url.origin) return json({error:'Origine non autorizzata.'},403);
  if (path === '/auth/logout' && request.method === 'POST') return new Response(null,{status:204,headers:{'Set-Cookie':cookie(SESSION,'',0),'Cache-Control':'no-store'}});
  if (path === '/api/feedback') {
    if (['GET','HEAD'].includes(request.method)) {
      const object = await store.get(root(env)+'current.json');
      if (!object) return json({draft:null},200,{ETag:'"empty"'});
      const headers = {'Content-Type':'application/json','Cache-Control':'no-store',ETag:object.httpEtag};
      return new Response(request.method === 'HEAD' ? null : object.body,{headers});
    }
    if (request.method === 'PUT') {
      const length = Number(request.headers.get('Content-Length') || 0);
      if (length > 8*1024*1024) return json({error:'Documento troppo grande.'},413);
      const text = await request.text();
      if (encoder.encode(text).length > 8*1024*1024) return json({error:'Documento troppo grande.'},413);
      let draft;
      try { draft = JSON.parse(text); } catch { return json({error:'JSON non valido.'},400); }
      if (!validDraft(draft)) return json({error:'Documento non valido.'},400);
      // A draft references only fully uploaded immutable files belonging to this owner.
      for (const file of draftFiles(draft)) {
        const stored = await store.head(root(env)+'files/'+file.storageKey);
        if (!stored || stored.size !== file.size) return json({error:'Allegato non ancora salvato.'},400);
      }
      const match = request.headers.get('If-Match');
      if (!match) return json({error:'Versione del documento obbligatoria.'},428);
      // Compression may weaken an HTTP ETag without changing the database revision.
      const revisionTag = match.replace(/^W\//,'');
      draft.updated = new Date().toISOString();
      const object = await store.put(root(env)+'current.json',JSON.stringify(draft),{onlyIf:revisionTag === '"empty"' ? {etagDoesNotMatch:'*'} : {etagMatches:revisionTag.replace(/^"|"$/g,'')},httpMetadata:{contentType:'application/json'}});
      if (!object) return json({error:'La versione salvata nel cloud è cambiata. Esporta il JSON prima di ricaricare.'},412);
      return json({updated:draft.updated},200,{ETag:object.httpEtag});
    }
    return json({error:'Metodo non consentito.'},405);
  }
  const fileKey = path.startsWith('/api/files/') ? path.slice('/api/files/'.length) : '';
  if (storageKey(fileKey)) {
    if (request.method === 'GET') {
      const object = await store.get(root(env)+'files/'+fileKey);
      return object ? new Response(object.body,{headers:{'Content-Type':'application/octet-stream','Content-Disposition':'attachment','Cache-Control':'private, max-age=86400','X-Content-Type-Options':'nosniff'}}) : json({error:'Allegato non trovato.'},404);
    }
    if (request.method === 'PUT') {
      if (Number(request.headers.get('Content-Length') || 0) > MAX_FILE) return json({error:'Allegato troppo grande.'},413);
      const bytes = await request.arrayBuffer();
      if (!bytes.byteLength || bytes.byteLength > MAX_FILE) return json({error:'Dimensione allegato non valida.'},413);
      const digest = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),byte => byte.toString(16).padStart(2,'0')).join('');
      if (digest !== fileKey) return json({error:'Allegato incompleto o non valido.'},400);
      await store.put(root(env)+'files/'+fileKey,bytes,{onlyIf:{etagDoesNotMatch:'*'},httpMetadata:{contentType:'application/octet-stream'}});
      return new Response(null,{status:204,headers:{'Cache-Control':'no-store'}});
    }
  }
  return json({error:'Percorso non trovato.'},404);
}
const CONTENT_SECURITY_POLICY = ["default-src 'none'","script-src 'self'","style-src 'self'","img-src 'self' blob:","font-src 'self'","connect-src 'self'","manifest-src 'self'","base-uri 'none'","form-action 'none'","frame-ancestors 'none'"].join('; ');
export default {
  async fetch(request,env) {
    let response;
    try { response = await handle(request,env); }
    catch { response = json({error:'Servizio cloud temporaneamente non disponibile. Le modifiche non sono state confermate.'},503); }
    const protectedResponse = new Response(response.body,response);
    // Every answered call of the page renews a session that is in use; logout clears it instead.
    const path = new URL(request.url).pathname;
    if ((path.startsWith('/api/') || path === '/auth/me') && response.status < 400) {
      const renewed = await renewal(request,env);
      if (renewed) protectedResponse.headers.append('Set-Cookie',renewed);
    }
    protectedResponse.headers.set('X-Content-Type-Options','nosniff');
    protectedResponse.headers.set('Referrer-Policy','same-origin');
    // Second line of defence for the page: only its own scripts, styles, fonts and API, and
    // images only from itself or from the attachments the page holds in memory (blob:).
    if ((protectedResponse.headers.get('Content-Type') || '').startsWith('text/html'))
      protectedResponse.headers.set('Content-Security-Policy',CONTENT_SECURITY_POLICY);
    return protectedResponse;
  }
};
