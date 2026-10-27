// Optional server-side Google Places integration. No API key is shipped to the app.
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type','Access-Control-Allow-Methods':'POST,OPTIONS'};
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{...cors,'Cache-Control':'no-store'}});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});if(req.method!=='POST')return json({error:'Method not allowed'},405);
 const url=Deno.env.get('SUPABASE_URL'),anon=Deno.env.get('SUPABASE_ANON_KEY'),key=Deno.env.get('GOOGLE_PLACES_API_KEY'),bearer=req.headers.get('Authorization');
 if(!url||!anon||!bearer?.startsWith('Bearer '))return json({error:'Unauthorized'},401);
 try{
 const headers={apikey:anon,Authorization:bearer,'Content-Type':'application/json'};
 const profile=await fetch(url+'/rest/v1/rpc/get_verified_profile',{method:'POST',headers,body:'{}',signal:AbortSignal.timeout(10000)});if(!profile.ok||!(await profile.json())?.phone)return json({error:'Unauthorized'},401);
 if(!key)return json({code:'not_configured',message:'Google Maps-ის ობიექტების ძიება ჯერ არ არის ჩართული.'},503);
 const input=await req.json(),lat=input.lat,lng=input.lng,radius=input.radius;
 if(typeof lat!=='number'||typeof lng!=='number'||typeof radius!=='number'||!Number.isFinite(lat)||!Number.isFinite(lng)||!Number.isFinite(radius)||Math.abs(lat)>90||Math.abs(lng)>180||radius<500||radius>5000)return json({error:'Invalid coordinates'},400);
 const quota=await fetch(url+'/rest/v1/rpc/places_quota_v432',{method:'POST',headers,body:'{}',signal:AbortSignal.timeout(10000)});if(!quota.ok||await quota.json()!==true)return json({message:'ძიების ლიმიტი ამოიწურა. მოგვიანებით სცადე.'},429);
 const response=await fetch('https://places.googleapis.com/v1/places:searchNearby',{method:'POST',headers:{'Content-Type':'application/json','X-Goog-Api-Key':key,'X-Goog-FieldMask':'places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.googleMapsUri,places.attributions'},body:JSON.stringify({maxResultCount:20,rankPreference:'DISTANCE',locationRestriction:{circle:{center:{latitude:lat,longitude:lng},radius}}}),signal:AbortSignal.timeout(15000)});
 if(!response.ok)return json({message:'Google Maps-ის მონაცემები დროებით მიუწვდომელია.'},502);const data=await response.json();
 return json({items:(data.places||[]).slice(0,20).map((p:any)=>({id:p.id,name:p.displayName?.text,address:p.formattedAddress,lat:p.location?.latitude,lng:p.location?.longitude,rating:p.rating,ratingCount:p.userRatingCount,url:p.googleMapsUri,attributions:p.attributions||[]}))});
 }catch{return json({message:'ობიექტები ვერ ჩაიტვირთა. სცადე ხელახლა.'},502)}
});
