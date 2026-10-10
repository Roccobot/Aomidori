// The recovery without the GitHub CLI (feedback-read.mjs --prepare and --open), on a synthetic
// round: the key stays in the private folder until the round is open, and goes after.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,existsSync,statSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {seal} from '../cloud/feedback/feedback-transfer.mjs';

const tool=join(dirname(fileURLToPath(import.meta.url)),'feedback-read.mjs');
const base=mkdtempSync(join(tmpdir(),'aomidori-read-test-'));
try {
  const dir=join(base,'key'),output=join(base,'out','giro.json');
  const inputs=JSON.parse(execFileSync('node',[tool,'--prepare','--dir',dir,'--version','4.33'],{encoding:'utf8'}));
  assert.match(inputs.request_id,/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.equal(inputs.version,'4.33');
  assert.equal(statSync(join(dir,'key.pem')).mode & 0o777,0o600);
  const pem=Buffer.from(inputs.public_key,'base64').toString('utf8');
  const payload={schema:1,project:'Aomidori',version:'4.33',completed:'2026-10-06T00:00:00Z',notes:'Nota di prova',
    extra:{images:[{name:'prova.svg',type:'image/svg+xml',data:'data:image/svg+xml;base64,'+Buffer.from('<svg/>').toString('base64')}]}};
  const envelope=join(base,'envelope.json');
  // A wrong file keeps the key, so the opening can be retried.
  writeFileSync(envelope,JSON.stringify(seal(payload,pem,'00000000-0000-4000-8000-000000000000')));
  assert.throws(()=>execFileSync('node',[tool,'--open',envelope,'--dir',dir,'--output',output],{stdio:'pipe'}));
  assert(existsSync(join(dir,'key.pem')),'a failed opening must keep the key');
  writeFileSync(envelope,JSON.stringify(seal(payload,pem,inputs.request_id)));
  // A round written inside the key folder would be deleted with it: refused, and the key stays.
  assert.throws(()=>execFileSync('node',[tool,'--open',envelope,'--dir',dir,'--output',join(dir,'giro.json')],{stdio:'pipe'}));
  assert(existsSync(join(dir,'key.pem')),'an output inside the key folder must keep the key');
  execFileSync('node',[tool,'--open',envelope,'--dir',dir,'--output',output],{stdio:'pipe'});
  const round=JSON.parse(readFileSync(output,'utf8'));
  assert.equal(round.notes,'Nota di prova');
  assert.equal(round.extra.images[0].data,'[file allegato-1.svg]');
  assert.equal(readFileSync(join(dirname(output),'allegato-1.svg'),'utf8'),'<svg/>');
  assert(!existsSync(dir),'the key must go once the round is open');
  console.log('Recupero senza gh: preparazione, apertura, allegati e chiave cancellata verificati.');
} finally { rmSync(base,{recursive:true,force:true}); }
