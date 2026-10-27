const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{...cors,'Cache-Control':'no-store'}});
const valid=(p:any)=>p&&typeof p.lat==='number'&&typeof p.lng==='number'&&Number.isFinite(p.lat)&&Number.isFinite(p.lng)&&Math.abs(p.lat)<=90&&Math.abs(p.lng)<=180;
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});if(req.method!=='POST')return json({code:'method'},405);
 const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),key=Deno.env.get('ORS_API_KEY'),authorization=req.headers.get('Authorization');
 if(!url||!anon||!authorization?.startsWith('Bearer '))return json({code:'unauthorized'},401);
 try{
 const headers={apikey:anon,Authorization:authorization,'Content-Type':'application/json'};
 const auth=await fetch(url+'/rest/v1/rpc/get_verified_profile',{method:'POST',headers,body:'{}',signal:AbortSignal.timeout(5000)});if(!auth.ok||!(await auth.json())?.phone)return json({code:'unauthorized'},401);
 if(!key)return json({code:'not_configured'},503);
 const input=await req.json();if(!valid(input.origin)||!['WALK','DRIVE'].includes(input.mode)||!Array.isArray(input.destinations)||!input.destinations.length||input.destinations.length>20||!input.destinations.every(valid))return json({code:'invalid'},400);
 const quota=await fetch(url+'/rest/v1/rpc/places_quota_v432',{method:'POST',headers,body:'{}',signal:AbortSignal.timeout(5000)});if(!quota.ok||await quota.json()!==true)return json({code:'quota'},429);
 const profile=input.mode==='WALK'?'foot-walking':'driving-car';
 const response=await fetch('https://api.openrouteservice.org/v2/matrix/'+profile,{method:'POST',headers:{'Content-Type':'application/json',Authorization:key},body:JSON.stringify({locations:[input.origin,...input.destinations].map((p:any)=>[p.lng,p.lat]),sources:['0'],destinations:input.destinations.map((_:any,i:number)=>String(i+1)),metrics:['distance','duration'],units:'m'}),signal:AbortSignal.timeout(8000)});
 if(!response.ok)return json({code:response.status===429?'quota':'provider_unavailable'},response.status===429?429:502);const data=await response.json();
 if(!Array.isArray(data.distances?.[0])||!Array.isArray(data.durations?.[0])||data.distances[0].length!==input.destinations.length||data.durations[0].length!==input.destinations.length)return json({code:'provider_unavailable'},502);
 if(!data.distances[0].some((d:any,i:number)=>Number.isFinite(d)&&d>=0&&Number.isFinite(data.durations[0][i])&&data.durations[0][i]>=0))return json({code:'no_route_data'},502);
 return json({items:input.destinations.map((_:any,index:number)=>{const meters=data.distances[0][index],seconds=data.durations[0][index];return {index,available:Number.isFinite(meters)&&meters>=0&&Number.isFinite(seconds)&&seconds>=0,meters,seconds};}),source:'openrouteservice',attribution:'© openrouteservice.org by HeiGIT | Map data © OpenStreetMap contributors',liveTraffic:false});
 }catch{return json({code:'unavailable'},502)}
});
