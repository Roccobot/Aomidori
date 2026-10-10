// Verify the deployment without signing in or reading private feedback.
const {CLOUDFLARE_ACCOUNT_ID:account,CLOUDFLARE_API_TOKEN:token} = process.env;
const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/workers/subdomain`,{headers:{Authorization:'Bearer '+token}});
if (!response.ok) throw Error('Impossibile verificare l\'indirizzo Workers dell\'account.');
const {result,success} = await response.json();
if (!success || !/^[a-z0-9-]+$/.test(result?.subdomain)) throw Error('Indirizzo Workers non configurato.');
const origin = `https://aomidori-feedback.${result.subdomain}.workers.dev`;
let status;
for (let attempt=0;attempt<12;attempt++) {
  status = (await fetch(origin+'/api/feedback')).status;
  if (status === 401) break;
  if (status === 200) throw Error('La bozza deve essere protetta prima di proseguire.');
  await new Promise(resolve=>setTimeout(resolve,2500));
}
if (status !== 401) throw Error('Il servizio deve rifiutare la lettura senza accesso, con stato 401.');
const page = await fetch(origin+'/feedback');
if (!page.ok || !(await page.text()).includes('data-feedback="agent"')) throw Error('Documento non disponibile all\'indirizzo cloud.');
process.stdout.write(origin+'/feedback');
