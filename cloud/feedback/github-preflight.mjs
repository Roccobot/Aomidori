// Check app credentials using a deliberately invalid token, without a user login.
const id=process.env.FEEDBACK_GITHUB_CLIENT_ID,secret=process.env.FEEDBACK_GITHUB_CLIENT_SECRET;
if (!id || !secret) throw Error('Configura Client ID e Client secret GitHub nei campi riservati.');
const response=await fetch('https://api.github.com/applications/'+encodeURIComponent(id)+'/token',{
  method:'POST',headers:{Authorization:'Basic '+Buffer.from(id+':'+secret).toString('base64'),
    Accept:'application/vnd.github+json','Content-Type':'application/json','User-Agent':'Aomidori-feedback'},
  body:JSON.stringify({access_token:'aomidori-feedback-configuration-check-not-a-real-token'}),
  redirect:'error',signal:AbortSignal.timeout(15000)
});
if (response.status!==404) {
  console.error('::error title=Credenziali GitHub::Verifica dell\'app GitHub non riuscita (HTTP '+response.status+'). Controlla che Client ID e Client secret provengano dall\'app registrata su GitHub.');
  process.exit(1);
}
console.log('Credenziali dell\'app GitHub verificate senza accedere ai repository o al feedback.');
