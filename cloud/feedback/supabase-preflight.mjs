// Check the configured remote project with synthetic data in a separate owner namespace.
// Never read or log the owner's feedback, headers, API keys or upstream error bodies.
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {SupabaseStore} from './supabase-store.mjs';
const url=process.env.FEEDBACK_SUPABASE_URL || readFileSync(new URL('./wrangler.toml',import.meta.url),'utf8').match(/^SUPABASE_URL = "([^"]+)"/m)?.[1];
const secret=process.env.FEEDBACK_SUPABASE_SECRET_KEY;
if (!url || !secret) throw Error('Configura URL Supabase e chiave server nel repository.');
const owner='0',prefix='feedback/v1/0/',key=prefix+'current.json';
const store=new SupabaseStore({SUPABASE_URL:url,SUPABASE_SECRET_KEY:secret,OWNER_ID:owner});
let stage='verifica del bucket privato';
try {
  const bucket=await (await store.request('/storage/v1/bucket/aomidori-feedback')).json();
  assert.equal(bucket.public,false,'Il bucket aomidori-feedback deve essere privato.');
  stage='lettura della bozza di prova';
  const current=await store.get(key);
  const draft={schema:1,project:'Aomidori',version:'3.24',installed:'3.24',device:'Verifica automatica del servizio',notes:'',entries:{},decisions:{},extra:{images:[]},updated:new Date().toISOString()};
  stage='primo salvataggio nel database';
  const first=await store.put(key,JSON.stringify(draft),{onlyIf:current ? {etagMatches:current.etag} : {etagDoesNotMatch:'*'}});
  assert(first,'Il salvataggio di prova deve riuscire.');
  stage='verifica del conflitto nel database';
  const contenders=await Promise.all(['A','B'].map(notes=>store.put(key,JSON.stringify({...draft,notes}),{onlyIf:{etagMatches:first.etag}})));
  assert.equal(contenders.filter(Boolean).length,1,'Una sola scrittura concorrente deve riuscire.');
  const winner=JSON.parse((await store.get(key)).body);
  assert.equal(winner.notes,contenders[0] ? 'A' : 'B');
  const bytes=Buffer.from('Aomidori: originali da verificare '+randomUUID());
  const digest=createHash('sha256').update(bytes).digest('hex'),fileKey=prefix+'files/'+digest;
  stage='caricamento dell\'allegato originale';
  await store.put(fileKey,bytes);
  stage='caricamento duplicato dell\'allegato';
  await store.put(fileKey,bytes);
  stage='verifica delle informazioni dell\'allegato';
  assert.equal((await store.head(fileKey)).size,bytes.length);
  stage='recupero dell\'allegato';
  const downloaded=Buffer.from(await new Response((await store.get(fileKey)).body).arrayBuffer());
  assert.deepEqual(downloaded,bytes,'Gli allegati devono rimanere identici.');
  // Remove only this synthetic file. Historical test drafts remain isolated under owner 0.
  stage='rimozione dell\'allegato sintetico';
  await store.request('/storage/v1/object/aomidori-feedback',{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:[fileKey]})});
  console.log('Supabase remoto: bucket privato, salvataggio, conflitto atomico e allegato originale verificati con dati sintetici separati dal feedback.');
} catch(error) {
  const status=Number.isInteger(error.status) ? ` HTTP ${error.status}` : '';
  const code=error.code && /^([A-Z][A-Za-z0-9_]{0,80}|[0-9]{5})$/.test(error.code) ? ` ${error.code}` : '';
  console.error('::error title=Archivio Supabase::Verifica Supabase non riuscita durante '+stage+'.'+status+code+' Controlla chiave server, esecuzione SQL e disponibilità del progetto.');
  process.exitCode=1;
}
