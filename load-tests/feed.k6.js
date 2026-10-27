import http from 'k6/http';
import {check,sleep} from 'k6';
import exec from 'k6/execution';
import {SharedArray} from 'k6/data';
import {validateTarget,validateUsers} from './guard.mjs';
const url=validateTarget(__ENV.STAGING_URL,__ENV.STAGING_REF,__ENV.PRODUCTION_REF,__ENV.CONFIRM_STAGING==='yes');
const peak=Number(__ENV.PEAK_VUS||10);
if(![10,100,1000,5000,10000,20000,30000].includes(peak))throw Error('Unsupported stage');
if(!__ENV.STAGING_ANON_KEY)throw Error('Missing staging publishable key');
const users=new SharedArray('synthetic sessions',()=>validateUsers(JSON.parse(open(__ENV.SESSIONS_FILE)),peak));
export const options={scenarios:{feed:{executor:'ramping-vus',startVUs:0,stages:[{duration:'2m',target:peak},{duration:'5m',target:peak},{duration:'1m',target:0}],gracefulRampDown:'30s'}},thresholds:{http_req_failed:[{threshold:'rate<0.01',abortOnFail:true,delayAbortEval:'30s'}],checks:['rate>0.99'],http_req_duration:['p(95)<1500','p(99)<3000']}};
export default function(){
 const user=users[exec.vu.idInTest-1];if(!user)throw Error('Missing unique session');
 const r=http.post(url+'/rest/v1/rpc/feed_page',JSON.stringify({p_before:null,p_before_id:null}),{headers:{apikey:__ENV.STAGING_ANON_KEY,Authorization:'Bearer '+user.access_token,'Content-Type':'application/json'},timeout:'10s',tags:{name:'feed_page'}});
 check(r,{'authorized bounded feed':r=>{try{const b=r.json();return r.status===200&&Array.isArray(b)&&b.length<=25}catch{return false}}});sleep(5+Math.random()*10);
}
