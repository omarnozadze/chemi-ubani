import {configuredHtml} from './public-config.mjs';
import fs from 'node:fs';
export function verifyRelease(root=process.cwd()){
 const read=p=>fs.readFileSync(root+'/'+p,'utf8'),pkg=JSON.parse(read('package.json')),app=JSON.parse(read('app.json')).expo,gradle=read('android/app/build.gradle');
 const version=pkg.version,code=Number(gradle.match(/\bversionCode\s+(\d+)/)?.[1]);
 if(!/^\d+\.\d+\.\d+$/.test(version))throw Error('Invalid package version');
 if(app.version!==version||gradle.match(/\bversionName\s+"([^"]+)"/)?.[1]!==version)throw Error('Version mismatch: package.json / app.json / Android');
 if(!Number.isInteger(code)||code<1||app.android.versionCode!==code)throw Error('Android versionCode mismatch');
 if(String(app.ios?.buildNumber)!==String(code))throw Error('iOS buildNumber mismatch');
 const html='prototype-v'+version+'.html';if(!fs.existsSync(root+'/'+html))throw Error('Current HTML is missing');
 for(const file of ['BUILD-APK.cmd','BUILD-AAB.ps1','BUILD-IOS-TESTFLIGHT.ps1'])if(!read(file).includes('embed-html.mjs '+html))throw Error(file+' points to an old HTML file');
 if(!pkg.scripts['eas-build-post-install']?.includes(html))throw Error('EAS build hook points to old HTML');
 const embedded=read('src/appHtml.js'),source=read(html);if(embedded!==`export const APP_HTML = ${JSON.stringify(configuredHtml(source,root))};\n`)throw Error('Embedded app is stale; run the HTML embedding step');
 if(!read('android/app/src/main/res/values/strings.xml').includes('>'+version+'<'))throw Error('Native runtime version mismatch');
 const lock=JSON.parse(read('package-lock.json'));if(lock.version!==version||lock.packages?.['']?.version!==version)throw Error('Lockfile version mismatch');
 return{version,code,html};
}
if(process.argv[1]?.endsWith('verify-release.mjs')){try{console.log('Release verified:',JSON.stringify(verifyRelease(process.argv[2])))}catch(e){console.error(e.message);process.exitCode=1}}
