// Preload before every regression test: no outbound socket or HTTP request is allowed.
import http from 'node:http';import https from 'node:https';import net from 'node:net';import tls from 'node:tls';import {syncBuiltinESMExports}from'node:module';
const deny=()=>{throw Error('NETWORK_DISABLED: regression tests must use fixtures')};
http.request=http.get=https.request=https.get=deny;net.connect=net.createConnection=tls.connect=deny;net.Socket.prototype.connect=deny;globalThis.fetch=deny;syncBuiltinESMExports();
