import {writeNativeConfig} from './public-config.mjs';
const config=writeNativeConfig();
if(process.argv.includes('--check') && (config.supabaseUrl==='https://example.invalid'||config.supabaseAnonKey==='YOUR_SUPABASE_ANON_KEY'||config.expoProjectId.startsWith('00000000'))){
 console.error('Fill config.public.local.json with your own public project settings before building.');process.exitCode=1;
}else console.log('Public configuration prepared. '+(config.supabaseUrl==='https://example.invalid'?'Unconfigured review mode; no production backend is selected.':'Local project settings loaded.'));
