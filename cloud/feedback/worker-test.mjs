import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import worker from './worker.mjs';
class Bucket {
  objects = new Map();
  async head(key) { const value=this.objects.get(key); return value ? {size:value.bytes.length,etag:value.etag,httpEtag:'"'+value.etag+'"'} : null; }
  async get(key) { const value=this.objects.get(key); return value ? {...await this.head(key),body:new Response(value.bytes).body} : null; }
  async put(key,body,options={}) {
    const existing=await this.head(key), condition=options.onlyIf;
    if (condition?.etagDoesNotMatch === '*' && existing || condition?.etagMatches && existing?.etag !== condition.etagMatches) return null;
    const bytes=typeof body==='string' ? Buffer.from(body) : Buffer.from(body);
    const etag=createHash('sha256').update(bytes).digest('hex');
    this.objects.set(key,{bytes,etag});return this.head(key);
  }
}
const env={FEEDBACK:new Bucket(),OWNER_ID:'10722164',SESSION_SECRET:'unit-test-secret-never-used-in-production',GITHUB_CLIENT_ID:'test-id',GITHUB_CLIENT_SECRET:'test-secret',ASSETS:{fetch:async()=>new Response('public page')}};
const origin='https://feedback.example';
const request=(path,options={})=>new Request(origin+path,options);
const realFetch=globalThis.fetch;
let profileId=10722164;
let profileLogin='Roccobot';
globalThis.fetch=async url=> {
  if (url==='https://github.com/login/oauth/access_token') return Response.json({access_token:'test-token'});
  if (url==='https://api.github.com/user') return Response.json({id:profileId,login:profileLogin});
  throw Error('Unexpected external request');
};
try {
  assert.equal((await worker.fetch(request('/api/feedback'),env)).status,401);
  assert.equal((await worker.fetch(request('/feedback'),env)).status,200);
  const config=await (await worker.fetch(request('/feedback-cloud-config.js'),env)).text();
  assert(!config.includes('test-secret') && config.includes('/api/feedback'));
  assert.equal((await worker.fetch(request('/api/feedback'),{...env,SESSION_SECRET:null})).status,503);
  const login=await worker.fetch(request('/auth/login'),env);
  const state=new URL(login.headers.get('Location')).searchParams.get('state');
  const stateCookie=login.headers.get('Set-Cookie').split(';')[0];
  assert.equal((await worker.fetch(request('/auth/callback?state=invalid&code=test',{headers:{Cookie:stateCookie}}),env)).status,400);
  profileId=999;
  assert.equal((await worker.fetch(request('/auth/callback?state='+state+'&code=test',{headers:{Cookie:stateCookie}}),env)).status,403);
  profileId=10722164;
  const callback=await worker.fetch(request('/auth/callback?state='+state+'&code=test',{headers:{Cookie:stateCookie}}),env);
  assert.equal(callback.status,302);
  const signedCookie=callback.headers.getSetCookie().find(value=>value.startsWith('__Host-aomidori-session='));
  assert(signedCookie.includes('HttpOnly') && signedCookie.includes('Secure') && signedCookie.includes('SameSite=Lax'));
  const sessionCookie=signedCookie.split(';')[0];
  const authenticated=(path,options={})=>request(path,{...options,headers:{Cookie:sessionCookie,Origin:origin,...options.headers}});
  assert.deepEqual(await (await worker.fetch(authenticated('/auth/me'),env)).json(),{authenticated:true,username:'Roccobot'});
  assert.deepEqual(await (await worker.fetch(request('/auth/me'),env)).json(),{authenticated:false,username:null});
  assert.equal((await worker.fetch(request('/api/feedback',{headers:{Cookie:sessionCookie+'tampered'}}),env)).status,401);
  const realNow=Date.now;
  try {
    Date.now=()=>realNow()+8*86400*1000;
    assert.equal((await worker.fetch(authenticated('/api/feedback'),env)).status,401);
    // A session in use renews itself (2026-10-06): not within a day of the last renewal, then
    // with a fresh week, until the cap from the login.
    Date.now=()=>realNow()+3600*1000;
    assert(!(await worker.fetch(authenticated('/api/feedback'),env)).headers.getSetCookie().length);
    Date.now=()=>realNow()+6*86400*1000;
    const renewed=(await worker.fetch(authenticated('/api/feedback'),env)).headers.getSetCookie().find(value=>value.startsWith('__Host-aomidori-session='));
    assert(renewed && renewed.includes('HttpOnly') && renewed.includes('Max-Age=604800'));
    const renewedCookie=renewed.split(';')[0];
    Date.now=()=>realNow()+12*86400*1000;
    assert.equal((await worker.fetch(request('/api/feedback',{headers:{Cookie:renewedCookie}}),env)).status,200);
    assert.equal((await worker.fetch(request('/api/feedback',{headers:{Cookie:sessionCookie}}),env)).status,401);
    let rolling=renewedCookie;
    for (let day=12; day<=66; day+=5) {
      Date.now=()=>realNow()+day*86400*1000;
      const next=(await worker.fetch(request('/api/feedback',{headers:{Cookie:rolling}}),env)).headers.getSetCookie().find(value=>value.startsWith('__Host-aomidori-session='));
      if (next) rolling=next.split(';')[0];
    }
    Date.now=()=>realNow()+70*86400*1000;
    assert.equal((await worker.fetch(request('/api/feedback',{headers:{Cookie:rolling}}),env)).status,401,'the session must end at the cap from the login');
  } finally { Date.now=realNow; }
  const initial=await worker.fetch(authenticated('/api/feedback'),env);
  assert.equal(initial.headers.get('ETag'),'"empty"');
  assert.deepEqual(await initial.json(),{draft:null});
  const draft={schema:1,project:'Aomidori',version:'3.24',installed:'3.24',device:'test',notes:'**note**',entries:{'3.14-03':{status:'',comment:'*commento*',images:[]}},decisions:{},extra:{images:[]}};
  const put=(etag,value=draft)=>worker.fetch(authenticated('/api/feedback',{method:'PUT',headers:{'If-Match':etag,'Content-Type':'application/json'},body:JSON.stringify(value)}),env);
  assert.equal((await worker.fetch(authenticated('/api/feedback',{method:'PUT',headers:{Origin:'https://other.example','If-Match':'"empty"'},body:JSON.stringify(draft)}),env)).status,403);
  assert.equal((await worker.fetch(authenticated('/api/feedback',{method:'PUT',body:JSON.stringify(draft)}),env)).status,428);
  const created=await put('"empty"');assert.equal(created.status,200);
  const firstTag=created.headers.get('ETag');
  assert.equal((await put('"empty"')).status,412);
  assert.equal((await put(firstTag,{...draft,notes:'**nuove note**'})).status,200);
  assert.equal((await put(firstTag)).status,412);
  let latest=await worker.fetch(authenticated('/api/feedback'),env);
  let etag=latest.headers.get('ETag');assert.equal((await latest.json()).notes,'**nuove note**');
  const bytes=Buffer.from('Original ZIP/SVG bytes for storage integrity');
  const digest=createHash('sha256').update(bytes).digest('hex');
  assert.equal((await worker.fetch(authenticated('/api/files/'+digest,{method:'PUT',body:bytes}),env)).status,204);
  assert.equal((await worker.fetch(authenticated('/api/files/'+digest,{method:'PUT',body:bytes}),env)).status,204);
  assert.equal((await worker.fetch(authenticated('/api/files/'+digest,{method:'PUT',body:'changed'}),env)).status,400);
  assert.equal((await worker.fetch(authenticated('/api/files/'+digest,{method:'PUT',body:Buffer.alloc(8*1024*1024+1)}),env)).status,413);
  const downloaded=await worker.fetch(authenticated('/api/files/'+digest),env);
  assert.equal(downloaded.headers.get('Content-Type'),'application/octet-stream');
  assert.deepEqual(Buffer.from(await downloaded.arrayBuffer()),bytes);
  const withFiles=structuredClone(draft);withFiles.extra.images.push({name:'originale.zip',type:'application/zip',size:bytes.length,storageKey:digest});
  assert.equal((await put(etag,withFiles)).status,200);
  latest=await worker.fetch(authenticated('/api/feedback'),env);etag=latest.headers.get('ETag');
  assert.equal((await put(etag,{...withFiles,extra:{images:[{...withFiles.extra.images[0],storageKey:'0'.repeat(64)}]}})).status,400);
  assert.equal((await put(etag,{...withFiles,extra:{images:[{...withFiles.extra.images[0],data:'data:application/zip;base64,AA=='}]}})).status,400);
  assert.equal((await worker.fetch(authenticated('/auth/logout',{method:'POST'}),env)).status,204);
  console.log('Worker: OAuth del proprietario, cookie riservati, origini, versione atomica, conflitti, allegati identici, limiti e configurazione verificati.');
} finally { globalThis.fetch=realFetch; }
