// Server-only adapter. The browser never receives Supabase credentials or endpoints.
export class SupabaseStore {
  constructor(env) {
    this.url = new URL(env.SUPABASE_URL);
    this.secret = env.SUPABASE_SECRET_KEY;
    this.owner = String(env.OWNER_ID);
    const local = this.url.protocol === 'http:' && ['127.0.0.1','localhost'].includes(this.url.hostname)
      && this.secret === 'development-supabase-test-key';
    if (!local && !(this.url.protocol === 'https:' && this.url.hostname.endsWith('.supabase.co')))
      throw Error('Indirizzo Supabase non valido.');
    if (!this.secret || !/^[0-9]{1,20}$/.test(this.owner)) throw Error('Archivio non configurato.');
    this.prefix = `feedback/v1/${this.owner}/`;
  }
  async request(path, options = {}, allowed = []) {
    const headers = new Headers(options.headers);
    headers.set('apikey',this.secret);
    // New sb_secret keys belong only in apikey; legacy JWT keys also need Authorization.
    if (this.secret.startsWith('eyJ')) headers.set('Authorization','Bearer '+this.secret);
    const response = await fetch(new URL(path,this.url),{...options,headers,redirect:'manual',signal:options.signal || AbortSignal.timeout(15000)});
    if (response.ok) return response;
    let code = '';
    try {
      const error = await response.json();
      code = error.code || error.error || '';
      if (allowed.includes('missing') && (response.status === 404 || ['NoSuchKey','NotFound'].includes(code) || error.statusCode === '404')) return null;
      if (allowed.includes('duplicate') && (response.status === 409 || ['Duplicate','KeyAlreadyExists'].includes(code))) return null;
    } catch { /* Never expose an upstream error body or request headers. */ }
    if (allowed.includes('missing') && response.status === 404) return null;
    const error = Error(`Archivio Supabase non disponibile (HTTP ${response.status}).`);
    error.status = response.status;
    error.code = /^([A-Z][A-Za-z0-9_]{0,80}|[0-9]{5})$/.test(code) ? code : '';
    throw error;
  }
  path(key) {
    if (!key.startsWith(this.prefix)) throw Error('Percorso dell\'archivio non valido.');
    return key.split('/').map(encodeURIComponent).join('/');
  }
  async current() {
    const response = await this.request('/rest/v1/aomidori_feedback_drafts?owner_id=eq.'+this.owner+'&select=draft,revision&limit=1');
    const rows = await response.json();
    if (!Array.isArray(rows) || rows.length > 1) throw Error('Documento cloud non valido.');
    const row = rows[0];
    if (!row?.draft) return null;
    if (!/^[a-f0-9-]{36}$/.test(row.revision)) throw Error('Versione cloud non valida.');
    return {httpEtag:'"'+row.revision+'"',etag:row.revision,body:JSON.stringify(row.draft)};
  }
  async head(key) {
    if (key === this.prefix+'current.json') return this.current();
    const response = await this.request('/storage/v1/object/info/aomidori-feedback/'+this.path(key),{},['missing']);
    if (!response) return null;
    const info = await response.json();
    if (!Number.isInteger(info.size) || info.size < 1) throw Error('Allegato cloud incompleto.');
    return {size:info.size};
  }
  async get(key) {
    if (key === this.prefix+'current.json') return this.current();
    const response = await this.request('/storage/v1/object/authenticated/aomidori-feedback/'+this.path(key),{},['missing']);
    return response ? {body:response.body} : null;
  }
  async put(key, body, options = {}) {
    if (key === this.prefix+'current.json') {
      const expected = options.onlyIf?.etagDoesNotMatch === '*' ? 'empty' : options.onlyIf?.etagMatches;
      if (!expected) throw Error('Versione obbligatoria.');
      const response = await this.request('/rest/v1/rpc/aomidori_feedback_save',{
        method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({p_owner_id:this.owner,p_expected_revision:expected,p_draft:JSON.parse(body)})
      });
      const saved = await response.json();
      if (saved === null) return null;
      if (!/^[a-f0-9-]{36}$/.test(saved.revision)) throw Error('Conferma di salvataggio non valida.');
      return {etag:saved.revision,httpEtag:'"'+saved.revision+'"'};
    }
    await this.request('/storage/v1/object/aomidori-feedback/'+this.path(key),{
      method:'POST',headers:{'Content-Type':'application/octet-stream','x-upsert':'false'},body
    },['duplicate']);
    return {size:body.byteLength};
  }
}
