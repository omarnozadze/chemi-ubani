import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);const {parse}=require('@babel/parser');
import fs from 'node:fs';import path from 'node:path';import vm from 'node:vm';
const ignored=new Set(['node_modules','.git','.expo','build','.gradle','dist']);
let files=0,errors=[];
function visit(dir){for(const e of fs.readdirSync(dir,{withFileTypes:true})){
 if(ignored.has(e.name))continue;const file=path.join(dir,e.name);
 if(e.isDirectory()){visit(file);continue;}
 if(['config.public.local.json','google-services.json','publicConfig.js','appHtml.js','local.properties','config.js'].includes(e.name))continue;
 if(/\.(jks|keystore|p12|p8|pem|apk|aab|ipa)$/i.test(e.name)||/firebase-adminsdk|service-account/i.test(e.name))errors.push(file+': prohibited artifact');
 if(!/\.(js|mjs|cjs|ts|json|html|sql|md|yml|ps1|cmd|properties)$/.test(e.name))continue;
 const s=fs.readFileSync(file,'utf8');files++;
 if(/-----BEGIN (?:RSA |EC )?PRIVATE KEY-----/.test(s))errors.push(file+': private key');
 if(/AIza[\w-]{30,}/.test(s))errors.push(file+': embedded Google project key');
 for(const token of s.match(/eyJ[\w-]+\.eyJ[\w-]+\.[\w-]+/g)||[]){try{const p=JSON.parse(Buffer.from(token.split('.')[1],'base64url'));if(p.role==='service_role')errors.push(file+': service-role JWT')}catch{}}
 if(file.startsWith('src'+path.sep)&&file.endsWith('.js')&&!/\bexport\b/.test(s))try{new vm.Script(s,{filename:file})}catch(e){errors.push(e.message)}
}}
visit('.');
try{parse(fs.readFileSync('App.js','utf8'),{sourceType:'module',plugins:['jsx']});}catch(e){errors.push('Native shell syntax: '+e.message);}
const version=JSON.parse(fs.readFileSync('package.json')).version;
const html=fs.readFileSync(`prototype-v${version}.html`,'utf8');
let scripts=0;for(const m of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)){if(!m[1].trim())continue;try{new vm.Script(m[1]);scripts++;}catch(e){errors.push('Inline script: '+e.message)}}
if(errors.length){console.error(errors.join('\n'));process.exitCode=1}else console.log(`PASS ${files} text files checked; ${scripts} inline scripts parsed. Pattern scan is not a complete security audit.`);
