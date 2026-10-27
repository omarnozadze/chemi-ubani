import {configuredHtml,writeNativeConfig} from './public-config.mjs';
import fs from 'node:fs';
import path from 'node:path';
import {replaceDialogs} from './dialogs-v433.mjs';

const arg = process.argv[2];
if (!arg) {
  console.error('Usage: npm run sync-html -- /path/to/latest-preview.html');
  process.exit(1);
}
const input = path.resolve(arg);
const releaseVersion=JSON.parse(fs.readFileSync('package.json','utf8')).version;
let html = fs.readFileSync(input, 'utf8');
html=html.replace(/<!-- RELEASE META START -->[\s\S]*?<!-- RELEASE META END -->/g,'');
html=html.replace('<head>','<head><!-- RELEASE META START --><script>window.APP_VERSION='+JSON.stringify(releaseVersion)+';</script><!-- RELEASE META END -->');
html = html.replace(/<!-- V423 START -->[\s\S]*?<!-- V423 END -->/g, '');
html = html.replace(/<!-- SMS AUTH START -->[\s\S]*?<!-- SMS AUTH END -->/g, '');
html = html.replace(/<!-- NOTIFICATION EVENTS START -->[\s\S]*?<!-- NOTIFICATION EVENTS END -->/g, '');
html = html.replace(/<!-- USABILITY START -->[\s\S]*?<!-- USABILITY END -->/g, '');
html = html.replace(/<!-- FIXES START -->[\s\S]*?<!-- FIXES END -->/g, '');
for(const tag of ['ROUTES449','COMPACT448','COMMUNITY447','POLISH446','THEME446','SUPPORT445','SIMPLIFY444','FIX442','WORKFLOW441','COMFORT440','EXPERIENCE439','DELETE436','REFINE435','UPLOAD434','COMMUNITY434','ACTIVITY434','DIALOG433','MANAGE433','CHAT STORAGE','RELIABILITY','FEED','ADMIN TOOLS','QUALITY','REALTIME','CONVERSATIONS','LOCATIONS','DESIGN','DAY REMINDERS','NAV432','COMMUNITIES432','ORDERS432','CHAT432','MARKET432','GOOGLE432'])html=html.replace(new RegExp('<!-- '+tag+' START -->[\\s\\S]*?<!-- '+tag+' END -->','g'),'');
html=html.replace(/<!-- POLLING START -->[\s\S]*?<!-- POLLING END -->/g,'');
html=html.replace('<head>','<head><!-- POLLING START --><script>\n'+fs.readFileSync(path.resolve('src/polling-v427.js'),'utf8')+'\n</script><!-- POLLING END -->');
const disk=fs.readFileSync(path.resolve('src/chat-storage-v425.js'),'utf8');
html=html.replace('</body>','<!-- CHAT STORAGE START --><script>\n'+disk+'\n</script><!-- CHAT STORAGE END --></body>');
const upgrade = fs.readFileSync(path.resolve('src/upgrade-v423.js'), 'utf8');
html = html.replace('</body>', '<!-- V423 START --><script>\n' + upgrade + '\n</script><!-- V423 END --></body>');
const auth = fs.readFileSync(path.resolve('src/sms-auth.js'), 'utf8');
html = html.replace('</body>', '<!-- SMS AUTH START --><script>\n' + auth + '\n</script><!-- SMS AUTH END --></body>');
const events = fs.readFileSync(path.resolve('src/notification-events.js'), 'utf8');
html = html.replace('</body>', '<!-- NOTIFICATION EVENTS START --><script>\n' + events + '\n</script><!-- NOTIFICATION EVENTS END --></body>');
const usability = fs.readFileSync(path.resolve('src/usability-v424.js'), 'utf8');
html = html.replace('</body>', '<!-- USABILITY START --><script>\n' + usability + '\n</script><!-- USABILITY END --></body>');
html=html.replace(/<!-- CAMPAIGNS START -->[\s\S]*?<!-- CAMPAIGNS END -->/g,'');
const campaigns=fs.readFileSync(path.resolve('src/admin-campaigns-v4241.js'),'utf8');
html=html.replace('</body>','<!-- CAMPAIGNS START --><script>\n'+campaigns+'\n</script><!-- CAMPAIGNS END --></body>');
const fixes = fs.readFileSync(path.resolve('src/fixes-v4241.js'), 'utf8');
html = html.replace('</body>', '<!-- FIXES START --><script>\n' + fixes + '\n</script><!-- FIXES END --></body>');
for(const [tag,file]of [['FEED','feed-v425.js'],['RELIABILITY','reliability-v425.js'],['ADMIN TOOLS','admin-tools-v426.js'],['QUALITY','quality-v428.js'],['REALTIME','realtime-v428.js'],['CONVERSATIONS','conversations-v429.js'],['LOCATIONS','locations-v430.js'],['DESIGN','design-v431.js'],['DAY REMINDERS','daily-reminders-v431.js'],['NAV432','navigation-v432.js'],['COMMUNITIES432','communities-v432.js'],['ORDERS432','orders-v432.js'],['CHAT432','chat-tools-v432.js'],['MARKET432','market-v432.js']]){const source=fs.readFileSync(path.resolve('src/'+file),'utf8');html=html.replace('</body>','<!-- '+tag+' START --><script>\n'+source+'\n</script><!-- '+tag+' END --></body>')}
html=html.replace('</body>','<!-- MANAGE433 START --><script>'+fs.readFileSync(path.resolve('src/manage-v433.js'),'utf8')+'</script><!-- MANAGE433 END --></body>');
for(const[tag,file]of [['UPLOAD434','uploads-v434.js'],['COMMUNITY434','community-v434.js'],['ACTIVITY434','activity-v434.js'],['REFINE435','refinements-v435.js'],['DELETE436','deletion-v436.js'],['EXPERIENCE439','experience-v439.js'],['COMFORT440','comfort-v440.js'],['WORKFLOW441','workflow-v441.js'],['FIX442','fixes-v442.js'],['SIMPLIFY444','simplify-v444.js'],['SUPPORT445','support-v445.js'],['POLISH446','polish-v446.js'],['COMMUNITY447','community-v447.js'],['COMPACT448','compact-v448.js'],['ROUTES449','routes-v449.js']])html=html.replace('</body>','<!-- '+tag+' START --><script>'+fs.readFileSync(path.resolve('src/'+file),'utf8')+'</script><!-- '+tag+' END --></body>');
html=html.replace(/<script>([\s\S]*?)<\/script>/g,(_,code)=>'<script>'+replaceDialogs(code)+'</script>');
html=html.replace('<head>','<head><!-- DIALOG433 START --><script>'+fs.readFileSync(path.resolve('src/dialogs-v433.js'),'utf8')+'</script><!-- DIALOG433 END -->');
html=html.replace('<head>','<head><!-- THEME446 START --><script>try{document.documentElement.dataset.theme=localStorage.getItem("chemi-theme446")==="dark"?"dark":"light"}catch{}</script><!-- THEME446 END -->');
fs.writeFileSync(input, html, 'utf8');
const output = path.resolve('src/appHtml.js');
fs.writeFileSync(output, `export const APP_HTML = ${JSON.stringify(configuredHtml(html))};\n`, 'utf8');
writeNativeConfig();
console.log(`Embedded ${input} -> ${output}`);
