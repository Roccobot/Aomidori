// Local-only Supabase HTTP fixture backed by the real PostgreSQL setup script.
import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {pathToFileURL} from 'node:url';
export async function testServer(port = 0) {
  const db = new PGlite();
  await db.exec('create role anon; create role authenticated; create role service_role bypassrls; create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);');
  await db.exec(await readFile(new URL('./supabase-setup.sql',import.meta.url),'utf8'));
  await db.exec('grant usage on schema storage to service_role; grant select on storage.buckets to service_role; set role service_role;');
  const files = new Map(), calls = [];
  const server = createServer(async (request,response) => {
    const reply = (body,status=200,type='application/json') => {
      response.writeHead(status,{'Content-Type':type});
      response.end(type==='application/json' ? JSON.stringify(body) : body);
    };
    if (request.headers.apikey !== 'development-supabase-test-key') return reply({error:'Unauthorized'},401);
    const url = new URL(request.url,'http://localhost');
    calls.push({path:url.pathname,method:request.method,authorization:request.headers.authorization});
    try {
      if (url.pathname === '/storage/v1/bucket/aomidori-feedback') return reply((await db.query('select * from storage.buckets where id=$1',['aomidori-feedback'])).rows[0]);
      if (url.pathname === '/rest/v1/aomidori_feedback_drafts') {
        const owner = (url.searchParams.get('owner_id') || '').replace(/^eq\./,'');
        return reply((await db.query('select draft,revision from public.aomidori_feedback_drafts where owner_id=$1',[owner])).rows);
      }
      if (url.pathname === '/rest/v1/aomidori_feedback_history') {
        const owner=(url.searchParams.get('owner_id') || '').replace(/^eq\./,'');
        const version=(url.searchParams.get('draft->>version') || '').replace(/^eq\./,'');
        const cutoff=(url.searchParams.get('saved_at') || '').replace(/^lte\./,'');
        if (url.searchParams.get('draft->>completed')!=='not.is.null') return reply({error:'Submitted only'},400);
        return reply((await db.query("select draft,revision from public.aomidori_feedback_history where owner_id=$1 and draft->>'completed' is not null and ($2='' or draft->>'version'=$2) and ($3='' or saved_at<=nullif($3,'')::timestamptz) order by saved_at desc limit 1",[owner,version,cutoff])).rows);
      }
      const chunks=[];
      for await (const chunk of request) chunks.push(chunk);
      const bytes=Buffer.concat(chunks);
      if (url.pathname === '/rest/v1/rpc/aomidori_feedback_save' && request.method === 'POST') {
        const args=JSON.parse(bytes.toString());
        return reply((await db.query('select public.aomidori_feedback_save($1,$2,$3) as result',[args.p_owner_id,args.p_expected_revision,JSON.stringify(args.p_draft)])).rows[0].result);
      }
      if (url.pathname === '/storage/v1/object/aomidori-feedback' && request.method === 'DELETE') {
        const {prefixes}=JSON.parse(bytes.toString());
        for (const key of prefixes) files.delete(key);
        return reply(prefixes.map(name=>({name})));
      }
      const match=/^\/storage\/v1\/object\/(info\/|authenticated\/)?aomidori-feedback\/(.+)$/.exec(url.pathname);
      if (match) {
        const key=decodeURIComponent(match[2]);
        if (request.method === 'POST' && !match[1]) {
          if (request.headers['x-upsert'] !== 'false') return reply({error:'Upsert prohibited'},400);
          if (files.has(key)) return reply({code:'KeyAlreadyExists'},400);
          files.set(key,bytes);return reply({Key:key});
        }
        if (!files.has(key)) return reply({code:'NoSuchKey',statusCode:'404'},400);
        return match[1]==='info/' ? reply({size:files.get(key).length}) : reply(files.get(key),200,'application/octet-stream');
      }
      return reply({error:'NotFound'},404);
    } catch (error) {
      return reply({code:error.code || 'InvalidRequest'},400);
    }
  });
  await new Promise(resolve=>server.listen(port,'127.0.0.1',resolve));
  return {url:'http://127.0.0.1:'+server.address().port,db,files,calls,
    close:async()=>{await new Promise(resolve=>server.close(resolve));await db.close();}};
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const fixture=await testServer(Number(process.argv[2] || 8790));
  console.log('Archivio PostgreSQL di prova pronto sulla porta '+new URL(fixture.url).port+'.');
  for (const signal of ['SIGINT','SIGTERM']) process.on(signal,async()=>{await fixture.close();process.exit(0);});
}
