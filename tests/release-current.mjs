import fs from 'node:fs';import path from 'node:path';import os from 'node:os';import assert from 'node:assert/strict';import{verifyRelease}from'../scripts/verify-release.mjs';
const pkg=JSON.parse(fs.readFileSync('package.json')),app=JSON.parse(fs.readFileSync('app.json')).expo;
const html=`prototype-v${pkg.version}.html`;
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'chemi-release-'));
const files=['package.json','package-lock.json','app.json','BUILD-APK.cmd','BUILD-AAB.ps1','BUILD-IOS-TESTFLIGHT.ps1','android/app/build.gradle','android/app/src/main/res/values/strings.xml','src/appHtml.js',html];
if(fs.existsSync('config.public.local.json')) files.push('config.public.local.json');
try{
 for(const file of files){fs.mkdirSync(path.dirname(dir+'/'+file),{recursive:true});fs.copyFileSync(file,dir+'/'+file);}
 assert.equal(verifyRelease(dir).version,pkg.version);
 const mutations=[['app.json',s=>{const a=JSON.parse(s);a.expo.ios.buildNumber='0';return JSON.stringify(a)},/iOS buildNumber mismatch/],['android/app/build.gradle',s=>s.replace(`versionCode ${app.android.versionCode}`,'versionCode 0'),/versionCode mismatch/],['BUILD-APK.cmd',s=>s.replace(html,'prototype-v0.0.0.html'),/old HTML/],['src/appHtml.js',s=>s+'// stale',/stale/]];
 for(const[file,change,pattern]of mutations){const original=fs.readFileSync(dir+'/'+file,'utf8');fs.writeFileSync(dir+'/'+file,change(original));assert.throws(()=>verifyRelease(dir),pattern);fs.writeFileSync(dir+'/'+file,original);}
 console.log('PASS release version consistency, stale embeds and wrong build targets rejected.');
}finally{fs.rmSync(dir,{recursive:true,force:true});}
