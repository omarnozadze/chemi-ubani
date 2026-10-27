import assert from 'node:assert/strict';import {validateTarget,validateUsers} from '../load-tests/guard.mjs';
assert.throws(()=>validateTarget('https://exampleprojectref0000.supabase.co','exampleprojectref0000'));assert.throws(()=>validateTarget('https://evil.test','abcdefghijklmnopqrst'));validateTarget('https://abcdefghijklmnopqrst.supabase.co','abcdefghijklmnopqrst','zyxwvutsrqponmlkjihg',true);
assert.throws(()=>validateTarget('https://abcdefghijklmnopqrst.supabase.co','abcdefghijklmnopqrst','abcdefghijklmnopqrst',true));
assert.throws(()=>validateTarget('https://evil.test','abcdefghijklmnopqrst','zyxwvutsrqponmlkjihg',true));
const u={user_id:'synthetic-1',access_token:'test',expires_at:Date.now()/1000+7200};assert.throws(()=>validateUsers([u,u],2));assert.throws(()=>validateUsers([u],2));assert.throws(()=>validateUsers([{...u,expires_at:0}],1));validateUsers([u],1);console.log('PASS: production blocked; exact target; unique fresh sessions.');
