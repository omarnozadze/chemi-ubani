import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import assert from 'node:assert/strict';
import {readPublicConfig,configuredHtml} from '../scripts/public-config.mjs';
const root=fs.mkdtempSync(path.join(os.tmpdir(),'chemi-config-'));
try {
 assert.equal(readPublicConfig(root).supabaseUrl,'https://example.invalid');
 const write=c=>fs.writeFileSync(path.join(root,'config.public.local.json'),JSON.stringify(c));
 write({supabaseAnonKey:'sb_secret_example'});assert.throws(()=>readPublicConfig(root),/Secret/);
 const jwt='eyJhbGciOiJIUzI1NiJ9.'+Buffer.from(JSON.stringify({role:'service_role'})).toString('base64url')+'.dummy';
 write({supabaseAnonKey:jwt});assert.throws(()=>readPublicConfig(root),/anon/);
 write({privateKey:'anything'});assert.throws(()=>readPublicConfig(root),/Unknown/);
 write({supabaseUrl:'http://example.test'});assert.throws(()=>readPublicConfig(root),/HTTPS/);
 write({supabaseAnonKey:'</script><script>alert(1)</script>'});
 assert.equal((configuredHtml('<head></head>',root).match(/<script>/g)||[]).length,1);
 console.log('PASS no production default; rejects privileged keys and unknown fields; escapes inline configuration.');
}finally{fs.rmSync(root,{recursive:true,force:true});}
