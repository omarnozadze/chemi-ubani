import fs from 'node:fs';
import path from 'node:path';
export function readPublicConfig(root=process.cwd()) {
 const file=path.join(root,'config.public.local.json');
 const raw=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')):{};
 const allowed=['supabaseUrl','supabaseAnonKey','expoProjectId'];
 for(const k of Object.keys(raw)) if(!allowed.includes(k)) throw Error('Unknown public config field: '+k);
 const c={supabaseUrl:'https://example.invalid',supabaseAnonKey:'YOUR_SUPABASE_ANON_KEY',expoProjectId:'00000000-0000-4000-8000-000000000000',...raw};
 if(!/^https:\/\//.test(c.supabaseUrl)) throw Error('Supabase URL must use HTTPS');
 if(typeof c.supabaseAnonKey!=='string')throw Error('Public key must be a string');
 if(c.supabaseAnonKey.startsWith('sb_secret_'))throw Error('Secret keys must never be embedded in the app');
 if(c.supabaseAnonKey.split('.').length===3){
  const claims=JSON.parse(Buffer.from(c.supabaseAnonKey.split('.')[1],'base64url').toString());
  if(claims.role!=='anon')throw Error('Only an anon JWT may be embedded in the app');
 }
 if(!/^[0-9a-f-]{36}$/i.test(c.expoProjectId))throw Error('Invalid Expo project ID');
 return c;
}
export function configuredHtml(html,root=process.cwd()) {
 const json=JSON.stringify(readPublicConfig(root)).replaceAll('<','\\u003c');
 return html.replace('<head>','<head><script>window.CHEMI_PUBLIC_CONFIG='+json+';</script>');
}
export function writeNativeConfig(root=process.cwd()){
 const c=readPublicConfig(root);
 fs.writeFileSync(path.join(root,'src/publicConfig.js'),'export const PUBLIC_CONFIG = '+JSON.stringify(c)+';\n');
 return c;
}
