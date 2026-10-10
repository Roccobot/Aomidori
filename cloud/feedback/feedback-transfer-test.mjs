import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync,randomUUID} from 'node:crypto';
import {testServer} from './supabase-test-server.mjs';
import {SupabaseStore} from './supabase-store.mjs';
import {seal,open,submittedFeedback} from './feedback-transfer.mjs';
const keys=generateKeyPairSync('rsa',{modulusLength:3072});
const other=generateKeyPairSync('rsa',{modulusLength:3072});
const pem=keys.publicKey.export({format:'pem',type:'spki'}),id=randomUUID();
const fixture=await testServer();
try {
  const env={SUPABASE_URL:fixture.url,SUPABASE_SECRET_KEY:'development-supabase-test-key',OWNER_ID:'0'};
  const store=new SupabaseStore(env);
  const draft={schema:1,project:'Aomidori',version:'3.24',installed:'3.24',device:'Mac di prova',notes:'Bozza non inviata',entries:{},decisions:{},extra:{images:[]},completed:null};
  let revision='empty';
  async function save(value) {
    const result=await store.put(store.prefix+'current.json',JSON.stringify(value),{onlyIf:revision==='empty' ? {etagDoesNotMatch:'*'} : {etagMatches:revision}});
    assert(result);revision=result.etag;
  }
  await assert.rejects(submittedFeedback(env),/Nessun giro inviato/);
  await save(draft);
  await assert.rejects(submittedFeedback(env),/Nessun giro inviato/);
  const bytes=Buffer.from([80,75,5,6,...Array(18).fill(0)]),hash=createHash('sha256').update(bytes).digest('hex');
  await store.put(store.prefix+'files/'+hash,bytes);
  const sent={...draft,notes:'Primo giro inviato',completed:new Date().toISOString(),extra:{images:[{name:'nome originale.zip',type:'application/zip',size:bytes.length,storageKey:hash}]}};
  await save(sent);
  const submittedRevision=revision;
  await save({...draft,notes:'Modifica privata successiva, non ancora inviata'});
  const payload=await submittedFeedback(env);
  assert.equal(payload.notes,'Primo giro inviato');
  assert.equal(payload.cloudRevision,submittedRevision);
  assert.equal(payload.extra.images[0].name,'nome originale.zip');
  assert.deepEqual(Buffer.from(payload.extra.images[0].data.split(',')[1],'base64'),bytes);
  assert(!('storageKey' in payload.extra.images[0]));
  const before=await fixture.db.query('select count(*)::int as count from public.aomidori_feedback_history');
  const envelope=seal(payload,pem,id);
  assert(!JSON.stringify(envelope).includes('Primo giro inviato'));
  assert(!JSON.stringify(envelope).includes('nome originale.zip'));
  assert.deepEqual(open(envelope,keys.privateKey,id),payload);
  assert.throws(()=>open(envelope,other.privateKey,id));
  assert.throws(()=>open(envelope,keys.privateKey,randomUUID()));
  const tampered=structuredClone(envelope);
  const changed=Buffer.from(tampered.ciphertext,'base64');changed[0]^=1;tampered.ciphertext=changed.toString('base64');
  assert.throws(()=>open(tampered,keys.privateKey,id));
  assert.throws(()=>seal(payload,generateKeyPairSync('rsa',{modulusLength:1024}).publicKey.export({format:'pem',type:'spki'}),id));
  assert.deepEqual((await fixture.db.query('select count(*)::int as count from public.aomidori_feedback_history')).rows,before.rows);
  assert.equal(JSON.parse((await store.get(store.prefix+'current.json')).body).notes,'Modifica privata successiva, non ancora inviata');
  const requestedAt=new Date().toISOString();
  // The second send must come strictly after the request. PGlite's now() has millisecond
  // resolution and matched Date.now() in 284 samples out of 300 (measured), so a save in the
  // same millisecond counted as 'not after the request' and the test failed once on GitHub.
  while (Date.now()<=Date.parse(requestedAt)) await new Promise(r=>setTimeout(r,1));
  await save({...sent,notes:'Secondo invio, versione aggiornata'});
  assert.equal((await submittedFeedback(env)).notes,'Secondo invio, versione aggiornata');
  assert.equal((await submittedFeedback(env,'',requestedAt)).notes,'Primo giro inviato');
  await assert.rejects(submittedFeedback({...env,OWNER_ID:'1'}),/Nessun giro inviato/);
  await assert.rejects(submittedFeedback(env,'3.14'),/Nessun giro inviato/);
  await assert.rejects(submittedFeedback(env,'3.24&owner_id=eq.1'),/Versione richiesta/);
  fixture.files.set(store.prefix+'files/'+hash,Buffer.from('allegato alterato'));
  await assert.rejects(submittedFeedback(env),/incompleto/);
  console.log('Trasferimento: solo ultimo giro inviato, modifiche successive escluse, nuovo invio, originali, lettura senza scritture, cifratura, chiave diversa e manomissioni verificati.');
} finally {await fixture.close();}
