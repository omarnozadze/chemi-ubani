import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
const require=createRequire(path.resolve('tooling/package.json'));
const env={...process.env};
for(const [key,pkg] of [['JSDOM_MODULE','jsdom'],['INDEXEDDB_MODULE','fake-indexeddb'],['PGLITE_MODULE','@electric-sql/pglite']]) {
 try {env[key]=pathToFileURL(require.resolve(pkg)).href;}catch{console.error('Install test tools: npm ci --prefix tooling');process.exit(1);}
}
const tests=['config-public.mjs','release-current.mjs','push-v442.mjs','polling-v427.mjs','load-guard-v427.mjs','routes-edge-v451.mjs','routes-v455.mjs'];
let failed=0;
for(const file of tests){
 const r=spawnSync(process.execPath,['--import','./tests/no-network.mjs','tests/'+file],{env,encoding:'utf8',timeout:60000});
 console.log('\n'+file);process.stdout.write(r.stdout||'');process.stderr.write(r.stderr||'');
 if(r.status!==0){failed++;console.error(r.error?.message||'Exit '+r.status);}
}
console.log(`\n${tests.length-failed}/${tests.length} selected tests passed.`);
process.exitCode=failed?1:0;
