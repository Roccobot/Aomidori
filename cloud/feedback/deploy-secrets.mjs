// Pipe this output straight into Wrangler, never to logs or tracked files.
import {readFileSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
const configured = JSON.parse(readFileSync(process.argv[2],'utf8'));
if (!process.env.FEEDBACK_GITHUB_CLIENT_ID || !process.env.FEEDBACK_GITHUB_CLIENT_SECRET || !process.env.FEEDBACK_SUPABASE_SECRET_KEY) throw Error('Configura le credenziali GitHub e Supabase nei campi riservati del repository.');
const secrets = {GITHUB_CLIENT_ID:process.env.FEEDBACK_GITHUB_CLIENT_ID,GITHUB_CLIENT_SECRET:process.env.FEEDBACK_GITHUB_CLIENT_SECRET,SUPABASE_SECRET_KEY:process.env.FEEDBACK_SUPABASE_SECRET_KEY};
if (!configured.some(secret=>secret.name === 'SESSION_SECRET')) secrets.SESSION_SECRET = randomBytes(32).toString('hex');
process.stdout.write(JSON.stringify(secrets));
