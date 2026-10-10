import assert from 'node:assert/strict';
import {createHmac,createHash} from 'node:crypto';
import worker from './worker.mjs';
import {SupabaseStore} from './supabase-store.mjs';
import {testServer} from './supabase-test-server.mjs';
const fixture=await testServer();
try {
  const env={SUPABASE_URL:fixture.url,SUPABASE_SECRET_KEY:'development-supabase-test-key',OWNER_ID:'10722164',SESSION_SECRET:'development-test-secret',GITHUB_CLIENT_ID:'test-id',GITHUB_CLIENT_SECRET:'test-secret'};
  const body=Buffer.from(JSON.stringify({kind:'session',owner:10722164,exp:Date.now()/1000+3600})).toString('base64url');
  const cookie='__Host-aomidori-session='+body+'.'+createHmac('sha256',env.SESSION_SECRET).update(body).digest('base64url');
  const origin='https://feedback.example';
  const request=(path,options={})=>new Request(origin+path,{...options,headers:{Cookie:cookie,Origin:origin,...options.headers}});
  const draft={schema:1,project:'Aomidori',version:'3.24',installed:'3.24',device:'test',notes:'Riscontro originale',entries:{},decisions:{},extra:{images:[]}};
  const put=(etag,value=draft)=>worker.fetch(request('/api/feedback',{method:'PUT',headers:{'If-Match':etag},body:JSON.stringify(value)}),env);
  assert.throws(()=>new SupabaseStore({...env,SUPABASE_SECRET_KEY:'sb_secret_invalid_on_http'}));
  assert.equal((await worker.fetch(new Request(origin+'/api/feedback'),env)).status,401);
  const initial=await worker.fetch(request('/api/feedback'),env);
  assert.deepEqual(await initial.json(),{draft:null});
  assert.equal(initial.headers.get('ETag'),'"empty"');
  const created=await put('W/"empty"');assert.equal(created.status,200);
  const firstTag=created.headers.get('ETag');
  assert.equal((await put('W/"empty"')).status,412);
  const concurrent=await Promise.all([put('W/'+firstTag,{...draft,notes:'Dal primo browser'}),put(firstTag,{...draft,notes:'Dal computer'})]);
  assert.deepEqual(concurrent.map(result=>result.status).sort(),[200,412]);
  let latest=await worker.fetch(request('/api/feedback'),env);
  assert.equal((await latest.json()).notes,concurrent[0].status===200 ? 'Dal primo browser' : 'Dal computer');
  const currentTag=latest.headers.get('ETag');
  assert.equal((await put(firstTag)).status,412);
  assert.equal((await put('W/'+firstTag)).status,412);
  const files=[{name:'originale.svg',type:'image/svg+xml',bytes:Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><text>Originale</text></svg>')},
    {name:'originale.zip',type:'application/zip',bytes:Buffer.from([80,75,5,6,...Array(18).fill(0)])}];
  for(const file of files) {
    file.storageKey=createHash('sha256').update(file.bytes).digest('hex');
    const upload=()=>worker.fetch(request('/api/files/'+file.storageKey,{method:'PUT',body:file.bytes}),env);
    assert.equal((await upload()).status,204);assert.equal((await upload()).status,204);
    const response=await worker.fetch(request('/api/files/'+file.storageKey),env);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()),file.bytes);
  }
  assert.equal(fixture.files.size,2);
  const withFiles={...draft,extra:{images:files.map(file=>({name:file.name,type:file.type,size:file.bytes.length,storageKey:file.storageKey}))}};
  assert.equal((await put(currentTag,withFiles)).status,200);
  latest=await worker.fetch(request('/api/feedback'),env);
  const tag=latest.headers.get('ETag');
  assert.deepEqual((await latest.json()).extra.images,withFiles.extra.images);
  const missing=structuredClone(withFiles);missing.extra.images[0].storageKey='0'.repeat(64);
  assert.equal((await put(tag,missing)).status,400);
  const wrongSize=structuredClone(withFiles);wrongSize.extra.images[0].size++;
  assert.equal((await put(tag,wrongSize)).status,400);
  assert.equal(fixture.calls.filter(call=>call.authorization!==undefined).length,0);
  assert.equal((await fixture.db.query('select count(*)::int as count from public.aomidori_feedback_history')).rows[0].count,3);
  assert.equal((await worker.fetch(request('/api/feedback'),{...env,SUPABASE_SECRET_KEY:'wrong-key'})).status,503);
  console.log('Supabase: Worker reale, HTTP e PostgreSQL, due scritture concorrenti, revisioni, SVG/ZIP identici, duplicati, riferimenti, chiave solo server ed errori verificati.');
} finally {await fixture.close();}
