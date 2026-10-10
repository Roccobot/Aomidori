import {readFileSync,mkdirSync,writeFileSync} from 'node:fs';
import {recipientKey,seal,submittedFeedback} from './feedback-transfer.mjs';
import {createHash} from 'node:crypto';
import {SupabaseStore} from './supabase-store.mjs';
try {
  const config=readFileSync(new URL('./wrangler.toml',import.meta.url),'utf8');
  const pem=Buffer.from(process.env.FEEDBACK_RECIPIENT_KEY || '', 'base64').toString('utf8');
  recipientKey(pem);
  const env={
    SUPABASE_URL:config.match(/^SUPABASE_URL = "([^"]+)"/m)?.[1],
    OWNER_ID:config.match(/^OWNER_ID = "([^"]+)"/m)?.[1],
    SUPABASE_SECRET_KEY:process.env.FEEDBACK_SUPABASE_SECRET_KEY
  };
  let payload;
  if (process.env.FEEDBACK_VERIFY_ONLY==='true') {
    // Leading zeroes cannot match a real GitHub owner's canonical numeric ID.
    const owner='0'+BigInt('0x'+process.env.FEEDBACK_REQUEST_ID.slice(0,8)).toString();
    const synthetic={...env,OWNER_ID:owner},store=new SupabaseStore(synthetic);
    const bytes=Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0h1"/></svg>');
    const hash=createHash('sha256').update(bytes).digest('hex');
    const file=store.prefix+'files/'+hash;
    await store.put(file,bytes);
    const draft={schema:1,project:'Aomidori',version:'0.00',installed:'0.00',device:'Verifica',notes:'Verifica trasferimento',entries:{},decisions:{},extra:{images:[{name:'verifica.svg',type:'image/svg+xml',size:bytes.length,storageKey:hash}]},completed:new Date().toISOString()};
    const current=await store.get(store.prefix+'current.json');
    const saved=await store.put(store.prefix+'current.json',JSON.stringify(draft),{onlyIf:current ? {etagMatches:current.etag} : {etagDoesNotMatch:'*'}});
    if (!saved) throw Error('Verifica concorrente non riuscita.');
    payload=await submittedFeedback(synthetic,'0.00',new Date().toISOString());
    await store.request('/storage/v1/object/aomidori-feedback',{method:'DELETE',headers:{'Content-Type':'application/json'},body:JSON.stringify({prefixes:[file]})});
  } else {
    payload=await submittedFeedback(env,process.env.FEEDBACK_VERSION || '',process.env.FEEDBACK_REQUESTED_AT || '');
  }
  const envelope=seal(payload,pem,process.env.FEEDBACK_REQUEST_ID);
  mkdirSync('/tmp/aomidori-feedback-export',{recursive:true,mode:0o700});
  // Only ciphertext reaches an artifact. No draft, filenames or credentials enter logs.
  writeFileSync('/tmp/aomidori-feedback-export/feedback-envelope.json',JSON.stringify(envelope),{mode:0o600});
  console.log('Trasferimento cifrato del giro inviato preparato.');
} catch {
  console.error('Recupero non riuscito: controlla configurazione e presenza di un giro inviato. Nessun dato privato è stato pubblicato.');
  process.exitCode=1;
}
