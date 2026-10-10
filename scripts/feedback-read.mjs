// Run only after the owner explicitly asks the agent to read a submitted feedback round.
import {generateKeyPairSync,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,readFile,writeFile,rm,stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
import {open} from '../cloud/feedback/feedback-transfer.mjs';

const args=process.argv.slice(2);
function option(name,fallback='') {
  const index=args.indexOf(name);
  if (index<0) return fallback;
  if (!args[index+1] || args[index+1].startsWith('--')) throw Error('Opzione incompleta: '+name);
  return args[index+1];
}
async function gh(arguments_,input) {
  return new Promise((resolve_,reject)=>{
    const child=spawn('gh',arguments_,{stdio:['pipe','pipe','pipe']});
    let output='';
    child.stdout.on('data',data=>{output+=data;});
    // Never forward raw HTTP errors or signed download URLs to the conversation.
    child.stderr.on('data',()=>{});
    child.on('error',()=>reject(Error('GitHub CLI non disponibile.')));
    child.on('close',code=>code===0 ? resolve_(output) : reject(Error('Operazione GitHub non riuscita: '+arguments_[0])));
    child.stdin.end(input || '');
  });
}
const pause=ms=>new Promise(resolve_=>setTimeout(resolve_,ms));

/*
 * Sessions without the GitHub CLI (Claude Code in the cloud), since 2026-10-06: the recovery in
 * two commands, with the workflow started and its artifact downloaded by the session's own GitHub
 * tools in between. Until then every step was typed by hand (key, UUID, base64, folders), and
 * that is where the recoveries of 2026-10-06 went wrong.
 *   --prepare --dir D [--version X]  makes D (private), keeps the key and the request in it, and
 *                                    prints the inputs of `feedback-read.yml`;
 *   --open FILE --dir D --output OUT opens the artifact (ZIP or JSON), writes the round to OUT and
 *                                    its attachments next to it, and only then removes D with the key.
 */
async function prepare(dir) {
  const version=option('--version');
  if (version && !/^\d+\.\d{2}$/.test(version)) throw Error('Versione non valida.');
  await mkdir(dir,{recursive:true,mode:0o700});
  const {publicKey,privateKey}=generateKeyPairSync('rsa',{modulusLength:3072});
  const request={request_id:randomUUID(),requested_at:new Date().toISOString(),version,verify_only:String(args.includes('--verify-only'))};
  await writeFile(join(dir,'key.pem'),privateKey.export({format:'pem',type:'pkcs8'}),{mode:0o600,flag:'wx'});
  await writeFile(join(dir,'request.json'),JSON.stringify(request),{mode:0o600,flag:'wx'});
  console.log(JSON.stringify({...request,public_key:Buffer.from(publicKey.export({format:'pem',type:'spki'})).toString('base64')}));
}
async function envelopeFrom(file) {
  if (!file.endsWith('.zip')) return readFile(file,'utf8');
  return new Promise((resolve_,reject)=>{
    const child=spawn('unzip',['-p',file,'feedback-envelope.json'],{stdio:['ignore','pipe','ignore']});
    let output='';
    child.stdout.on('data',data=>{output+=data;});
    child.on('error',()=>reject(Error('unzip non disponibile.')));
    child.on('close',code=>code===0 ? resolve_(output) : reject(Error('Artefatto non leggibile.')));
  });
}
async function openEnvelope(file,dir) {
  const output=resolve(option('--output'));
  if (!option('--output')) throw Error('Manca --output.');
  // The key folder is deleted once the round is open, so a round written inside it would go
  // with it (it happened on 2026-10-06, and the round had to be recovered twice).
  const inside=relative(dir,output);
  if (!inside.startsWith('..') && !isAbsolute(inside)) throw Error('--output deve stare fuori da --dir, che si cancella dopo l\'apertura.');
  const request=JSON.parse(await readFile(join(dir,'request.json'),'utf8'));
  const payload=open(JSON.parse(await envelopeFrom(file)),await readFile(join(dir,'key.pem'),'utf8'),request.request_id);
  if (payload.schema!==1 || payload.project!=='Aomidori' || !payload.completed) throw Error('Giro recuperato non valido.');
  await mkdir(dirname(output),{recursive:true,mode:0o700});
  // Every attachment becomes a file with its own name, numbered, next to the round.
  let count=0;
  const files=[];
  const plain=JSON.parse(JSON.stringify(payload,(key,value)=>{
    const match=typeof value==='string' && value.match(/^data:([\w/+.-]+);base64,(.*)$/);
    if (!match) return value;
    const name=`allegato-${++count}.${match[1].split('/')[1].replace('svg+xml','svg')}`;
    files.push([name,Buffer.from(match[2],'base64')]);
    return `[file ${name}]`;
  }));
  for (const [name,bytes] of files) await writeFile(join(dirname(output),name),bytes,{mode:0o600,flag:'wx'});
  await writeFile(output,JSON.stringify(plain,null,2),{mode:0o600,flag:'wx'});
  console.log('Giro aperto: '+output+(files.length ? ', con '+files.length+' allegati accanto' : '')+'.');
}
const prepareMode=args.includes('--prepare'), openFile=option('--open');
if (prepareMode || openFile) {
  const dir=option('--dir');
  try {
    if (!dir) throw Error('Manca --dir.');
    if (prepareMode) await prepare(resolve(dir));
    else {
      await openEnvelope(resolve(openFile),resolve(dir));
      // The key lives until the round is open: a failed opening can be retried on the same
      // artifact, without a new request.
      await rm(resolve(dir),{recursive:true,force:true});
    }
  } catch (error) {
    console.error(error.message+(openFile ? ' La chiave resta in '+dir+': si può riprovare.' : ''));
    process.exitCode=1;
  }
  process.exit();
}
let temporary;
try {
  const verifyOnly=args.includes('--verify-only');
  const output=resolve(option('--output',join(tmpdir(),'aomidori-feedback-'+randomUUID(),'feedback.json')));
  const version=option('--version');
  if (version && !/^\d+\.\d{2}$/.test(version)) throw Error('Versione non valida.');
  const repo='Roccobot/Aomidori',requestId=randomUUID();
  // The private key exists only in this process, never in a workflow or repository.
  const {publicKey,privateKey}=generateKeyPairSync('rsa',{modulusLength:3072});
  const input={request_id:requestId,public_key:Buffer.from(publicKey.export({format:'pem',type:'spki'})).toString('base64'),version,verify_only:String(verifyOnly),requested_at:new Date().toISOString()};
  await gh(['workflow','run','feedback-read.yml','--repo',repo,'--ref','main','--json'],JSON.stringify(input));
  const deadline=Date.now()+10*60*1000;
  let run;
  while (Date.now()<deadline) {
    const runs=JSON.parse(await gh(['run','list','--repo',repo,'--workflow','feedback-read.yml','--event','workflow_dispatch','--limit','30','--json','databaseId,displayTitle,status,conclusion']));
    run=runs.find(item=>item.displayTitle==='Feedback richiesto '+requestId);
    if (run?.status==='completed') break;
    await pause(3000);
  }
  if (!run || run.status!=='completed' || run.conclusion!=='success') throw Error('Recupero non completato. Verifica il workflow Leggi feedback inviato e la presenza di un giro inviato.');
  temporary=await mkdtemp(join(tmpdir(),'aomidori-feedback-transfer-'));
  await gh(['run','download',String(run.databaseId),'--repo',repo,'--name','feedback-envelope','--dir',temporary]);
  const envelopePath=join(temporary,'feedback-envelope.json');
  if ((await stat(envelopePath)).size>60*1024*1024) throw Error('Trasferimento troppo grande.');
  const payload=open(JSON.parse(await readFile(envelopePath,'utf8')),privateKey,requestId);
  if (payload.schema!==1 || payload.project!=='Aomidori' || !payload.completed) throw Error('Giro recuperato non valido.');
  if (verifyOnly && payload.notes!=='Verifica trasferimento') throw Error('Prova del trasferimento non valida.');
  await mkdir(dirname(output),{recursive:true,mode:0o700});
  await writeFile(output,JSON.stringify(payload,null,2),{mode:0o600,flag:'wx'});
  // Remove the encrypted artifact after downloading; a failure does not expose plaintext.
  try {
    const artifacts=JSON.parse(await gh(['api',`repos/${repo}/actions/runs/${run.databaseId}/artifacts`]));
    for (const artifact of artifacts.artifacts || [])
      if (artifact.name==='feedback-envelope') await gh(['api','--method','DELETE',`repos/${repo}/actions/artifacts/${artifact.id}`]);
  } catch { console.log('Artefatto cifrato conservato fino alla scadenza di un giorno.'); }
  console.log(verifyOnly ? 'Prova del trasferimento verificata, nessun feedback personale letto.' : 'Ultimo giro inviato recuperato, senza modificare la bozza.');
  console.log('File privato: '+output);
} catch (error) {
  console.error(error.message);
  process.exitCode=1;
} finally { if (temporary) await rm(temporary,{recursive:true,force:true}); }
