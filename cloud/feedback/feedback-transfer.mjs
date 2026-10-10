import {createCipheriv,createDecipheriv,createHash,createPublicKey,publicEncrypt,privateDecrypt,randomBytes,constants} from 'node:crypto';
import {SupabaseStore} from './supabase-store.mjs';

const requestPattern=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const aad=id=>Buffer.from('Aomidori feedback transfer v1:'+id);
export function recipientKey(pem) {
  const key=createPublicKey(pem);
  if (key.asymmetricKeyType!=='rsa' || key.asymmetricKeyDetails.modulusLength<3072)
    throw Error('Chiave pubblica di trasferimento non valida.');
  return key;
}
export function seal(payload,pem,requestId) {
  if (!requestPattern.test(requestId)) throw Error('Richiesta di trasferimento non valida.');
  const key=randomBytes(32),nonce=randomBytes(12);
  const cipher=createCipheriv('aes-256-gcm',key,nonce);
  cipher.setAAD(aad(requestId));
  const ciphertext=Buffer.concat([cipher.update(JSON.stringify(payload),'utf8'),cipher.final()]);
  const wrappedKey=publicEncrypt({key:recipientKey(pem),padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},key);
  return {schema:1,requestId,cipher:'AES-256-GCM',wrappedKey:wrappedKey.toString('base64'),nonce:nonce.toString('base64'),tag:cipher.getAuthTag().toString('base64'),ciphertext:ciphertext.toString('base64')};
}
export function open(envelope,privateKey,requestId) {
  if (envelope.schema!==1 || envelope.cipher!=='AES-256-GCM' || envelope.requestId!==requestId || !requestPattern.test(requestId))
    throw Error('Trasferimento non valido.');
  for (const field of ['wrappedKey','nonce','tag','ciphertext'])
    if (typeof envelope[field]!=='string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(envelope[field])) throw Error('Trasferimento non valido.');
  const key=privateDecrypt({key:privateKey,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},Buffer.from(envelope.wrappedKey,'base64'));
  const decipher=createDecipheriv('aes-256-gcm',key,Buffer.from(envelope.nonce,'base64'));
  decipher.setAAD(aad(requestId));
  decipher.setAuthTag(Buffer.from(envelope.tag,'base64'));
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.ciphertext,'base64')),decipher.final()]).toString('utf8'));
}
export async function submittedFeedback(env,version='',notAfter='') {
  if (version && !/^\d+\.\d{2}$/.test(version)) throw Error('Versione richiesta non valida.');
  const store=new SupabaseStore(env);
  const query=new URLSearchParams({owner_id:'eq.'+store.owner,'draft->>completed':'not.is.null',select:'draft,revision',order:'saved_at.desc',limit:'1'});
  if (version) query.set('draft->>version','eq.'+version);
  if (notAfter) {
    if (!Number.isFinite(Date.parse(notAfter))) throw Error('Data della richiesta non valida.');
    query.set('saved_at','lte.'+new Date(notAfter).toISOString());
  }
  // Read only the last submitted snapshot, never subsequent edits in the current draft.
  const rows=await (await store.request('/rest/v1/aomidori_feedback_history?'+query)).json();
  if (!Array.isArray(rows) || rows.length!==1) throw Error('Nessun giro inviato disponibile. Premi Invia nel documento.');
  const {draft,revision}=rows[0];
  if (!draft || draft.schema!==1 || draft.project!=='Aomidori' || typeof draft.completed!=='string' || !Number.isFinite(Date.parse(draft.completed)) || !/^[a-f0-9-]{36}$/.test(revision))
    throw Error('Giro inviato non valido.');
  const files=[...Object.values(draft.entries || {}),draft.extra || {images:[]}].flatMap(entry=>entry.images || []);
  let total=0;
  for (const file of files) {
    if (!/^[a-f0-9]{64}$/.test(file.storageKey) || !Number.isInteger(file.size) || file.size<1 || file.size>8*1024*1024 ||
        !['image/png','image/jpeg','image/webp','image/gif','image/svg+xml','application/zip'].includes(file.type) || (total+=file.size)>20*1024*1024)
      throw Error('Allegati del giro non validi.');
    const object=await store.get(store.prefix+'files/'+file.storageKey);
    if (!object) throw Error('Allegato del giro non disponibile.');
    const bytes=Buffer.from(await new Response(object.body).arrayBuffer());
    if (bytes.length!==file.size || createHash('sha256').update(bytes).digest('hex')!==file.storageKey)
      throw Error('Allegato del giro incompleto.');
    file.data='data:'+file.type+';base64,'+bytes.toString('base64');
    delete file.storageKey;
  }
  return {...draft,cloudRevision:revision};
}
