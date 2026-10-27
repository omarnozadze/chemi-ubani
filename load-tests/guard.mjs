export function validateTarget(url,ref,productionRef,confirmed=false){
 if(!confirmed || !/^[a-z0-9]{20}$/.test(productionRef||'') || productionRef===ref)throw Error('Explicit staging confirmation and a different production reference are required');
 if(!/^[a-z0-9]{20}$/.test(ref||'')||ref==='exampleprojectref0000')throw Error('A separate staging project reference is required');
 if(url!==`https://${ref}.supabase.co`)throw Error('Target must match the staging reference exactly');return url;
}
export function validateUsers(users,count,now=Date.now()){
 if(!Array.isArray(users)||users.length<count)throw Error('One synthetic authenticated user per VU is required');
 const ids=new Set();for(const u of users){if(!u.user_id||ids.has(u.user_id)||!u.access_token||!(u.expires_at*1000>now+3600000))throw Error('Unique fresh synthetic sessions required');ids.add(u.user_id)}return users;
}
