import React, { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, AppState, BackHandler, Image, Linking, Modal, Platform, SafeAreaView, StatusBar, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { WebView } from 'react-native-webview';
import * as Notifications from 'expo-notifications';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { PUBLIC_CONFIG } from './src/publicConfig';
import { APP_HTML } from './src/appHtml';
import { createPushRegistration, withDeadline } from './src/push-registration-v442.mjs';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

const PHOTO_REMINDER_ID_KEY = 'daily-photo-reminder';

async function configureNotificationChannel() {
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('daily-photo', {
      name: 'ყოველდღიური ფოტო შეხსენება',
      importance: Notifications.AndroidImportance.DEFAULT,
      sound: 'default',
      vibrationPattern: [0, 200, 150, 200],
    });
  }
}

// v4.31: server checks whether today's photo exists. Cancel legacy 19:00 schedules.
async function setDailyPhotoReminder() {
  const existing = await Notifications.getAllScheduledNotificationsAsync();
  for (const item of existing) {
    if (item.content?.data?.kind === PHOTO_REMINDER_ID_KEY) {
      await Notifications.cancelScheduledNotificationAsync(item.identifier);
    }
  }
  return { enabled: false, serverManaged: true };
}

export default function App() {
  const webRef = useRef(null);
  const [dark446,setDark446]=useState(false);
  useEffect(() => { setDailyPhotoReminder().catch(() => {}); }, []);
  useEffect(() => {
    const listener = AppState.addEventListener('change', state => {
      if (state === 'active') pushController.current?.resume();
      webRef.current?.injectJavaScript(`window.appNativeActive=${state === 'active'}; window.activityConnection?.(); if(window.appNativeActive)window.appPoll?.wake();true;`);
    });
    return () => listener.remove();
  }, []);
  const pushTokenRef = useRef('');
  const pushController = useRef(null);
  const pushAck = useRef(null);
  if (!pushController.current) pushController.current = createPushRegistration({
    active: () => AppState.currentState !== 'background' && AppState.currentState !== 'inactive',
    status: (state, phone) => webRef.current?.injectJavaScript(`window.setPushStatus442?.(${JSON.stringify(state)},${JSON.stringify(phone)});true;`),
    acquire: async () => {
      if (Platform.OS === 'android') await Notifications.setNotificationChannelAsync('activity', {
        name: 'შეტყობინებები', importance: Notifications.AndroidImportance.HIGH,
        vibrationPattern: [0, 200, 100, 200], sound: 'default',
      });
      let permission = await Notifications.getPermissionsAsync();
      if (permission.status !== 'granted' && permission.canAskAgain !== false) permission = await Notifications.requestPermissionsAsync();
      if (permission.status !== 'granted') { const error = new Error('Permission denied'); error.code = 'permission_denied'; throw error; }
      const result = await withDeadline(Notifications.getExpoPushTokenAsync({ projectId: PUBLIC_CONFIG.expoProjectId }));
      return result.data;
    },
    deliver: (token, phone) => new Promise((resolve, reject) => {
      const id = `${Date.now()}-${Math.random()}`;
      const timeout = setTimeout(() => { if (pushAck.current?.id === id) pushAck.current = null; reject(new Error('Registration timed out')); }, 12000);
      pushAck.current = { id, finish: ok => { clearTimeout(timeout); pushAck.current = null; if (ok) { pushTokenRef.current = token; resolve(); } else reject(new Error('Registration incomplete')); } };
      webRef.current?.injectJavaScript(`window.handlePushRegistration?.(${JSON.stringify(token)},${JSON.stringify(phone)},${JSON.stringify(id)});true;`);
    }),
  });
  useEffect(() => () => { pushController.current.stop(); pushAck.current?.finish(false); }, []);
  const pendingPushOpen = useRef(false);
  const webReady = useRef(false);
  const [canGoBack, setCanGoBack] = useState(false);
  const [loading, setLoading] = useState(true);
  const [webError, setWebError] = useState('');
  const [webKey, setWebKey] = useState(0);
  const cameraRef = useRef(null);
  const [cameraOpen, setCameraOpen] = useState(false);
  const [cameraFacing, setCameraFacing] = useState('back');
  const [cameraReady, setCameraReady] = useState(false);
  const [captureBusy, setCaptureBusy] = useState(false);
  const [dailyBack, setDailyBack] = useState('');
  const [dailyFront, setDailyFront] = useState('');
  const [dualAutoCapture, setDualAutoCapture] = useState(false);
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();

  useEffect(() => {
    if (Platform.OS !== 'android') return;
    const sub = BackHandler.addEventListener('hardwareBackPress', () => {
      if(cameraOpen){closeDailyCamera();return true;}
      webRef.current?.injectJavaScript('window.handleNativeBack439?.();true;');
      return true;
    });
    return () => sub.remove();
  }, [cameraOpen]);

  useEffect(() => {
    const received = Notifications.addNotificationReceivedListener((notification) => {
      if (notification.request.content.data?.kind === 'activity') webRef.current?.injectJavaScript('window.handleActivitySignal?.(); true;');
    });
    const sub = Notifications.addNotificationResponseReceivedListener((response) => {
      if (response.notification.request.content.data?.kind === 'activity') {
        pendingPushOpen.current = response.notification.request.content.data;
        if (webReady.current) { webRef.current?.injectJavaScript(`window.handlePushOpen?.(${JSON.stringify(pendingPushOpen.current)}); true;`); pendingPushOpen.current = false; }
      }
      if (response.notification.request.content.data?.kind === PHOTO_REMINDER_ID_KEY) {
        setTimeout(() => webRef.current?.injectJavaScript('openDailyPhotoReminder(); true;'), 250);
      }
    });
    Notifications.getLastNotificationResponseAsync().then((response) => {
      if (response?.notification?.request?.content?.data?.kind === 'activity') {
        pendingPushOpen.current = response.notification.request.content.data;
        if (webReady.current) { webRef.current?.injectJavaScript(`window.handlePushOpen?.(${JSON.stringify(pendingPushOpen.current)}); true;`); pendingPushOpen.current = false; }
        Notifications.clearLastNotificationResponseAsync().catch(() => {});
      }
      if (response?.notification?.request?.content?.data?.kind === PHOTO_REMINDER_ID_KEY) {
        setTimeout(() => webRef.current?.injectJavaScript('openDailyPhotoReminder(); true;'), 900);
      }
    }).catch(() => {});
    return () => { sub.remove(); received.remove(); };
  }, []);



  const closeDailyCamera = () => {
    setCameraOpen(false); setCameraFacing('back'); setCameraReady(false); setCaptureBusy(false); setDualAutoCapture(false); setDailyBack(''); setDailyFront('');
  };

  const openDailyCameraNative = async () => {
    try {
      const permission = cameraPermission?.granted ? cameraPermission : await requestCameraPermission();
      if (!permission?.granted) {
        Alert.alert('კამერის უფლება', 'დღის ფოტოს გადასაღებად ჩართე Camera permission ტელეფონის Settings-იდან.');
        return;
      }
      setDailyBack(''); setDailyFront(''); setDualAutoCapture(false); setCameraFacing('back'); setCameraReady(false); setCameraOpen(true);
    } catch (e) {
      webRef.current?.injectJavaScript("window.reportAppIssue?.('camera_failed');true;");
      Alert.alert('კამერა ვერ გაიხსნა', String(e?.message || e));
    }
  };

  const captureDailyFrame = async () => {
    if (!cameraReady || captureBusy || !cameraRef.current) return;
    setCaptureBusy(true);
    try {
      const photo = await cameraRef.current.takePictureAsync({ base64: true, quality: 0.5, skipProcessing: false });
      if (!photo?.base64) throw new Error('ფოტო ვერ შეინახა');
      const data = `data:image/jpeg;base64,${photo.base64}`;
      if (cameraFacing === 'back' && !dailyBack) {
        setDailyBack(data);
        setDualAutoCapture(true);
        setCameraReady(false);
        setCameraFacing('front');
      } else {
        setDailyFront(data);
        setDualAutoCapture(false);
      }
    } catch (e) {
      setDualAutoCapture(false);
      webRef.current?.injectJavaScript("window.reportAppIssue?.('camera_failed');true;");
      Alert.alert('გადაღება ვერ მოხერხდა', String(e?.message || e));
    } finally { setCaptureBusy(false); }
  };


  useEffect(() => {
    if (!(cameraOpen && dualAutoCapture && cameraFacing === 'front' && dailyBack && !dailyFront && cameraReady && !captureBusy)) return;
    const timer = setTimeout(() => { captureDailyFrame(); }, 450);
    return () => clearTimeout(timer);
  }, [cameraOpen, dualAutoCapture, cameraFacing, dailyBack, dailyFront, cameraReady, captureBusy]);

  const useDailyPhotos = () => {
    if (!dailyBack || !dailyFront) return;
    const payload = JSON.stringify({ back: dailyBack, front: dailyFront });
    setCameraOpen(false);
    setTimeout(() => webRef.current?.injectJavaScript(`handleNativeDailyCameraResult(${payload}); true;`), 120);
  };

  // Send both captures straight to the single publish composer.
  useEffect(() => {
    if (cameraOpen && dailyBack && dailyFront && !captureBusy) useDailyPhotos();
  }, [cameraOpen, dailyBack, dailyFront, captureBusy]);

  const injected = `
    (function () {
      
      const originalOpen = window.open;
      window.open = function(url) {
        try {
          window.ReactNativeWebView.postMessage(JSON.stringify({ type: 'openExternal', url: String(url || '') }));
          return null;
        } catch (e) {
          return originalOpen ? originalOpen(url) : null;
        }
      };
      true;
    })();
  `;

  const onMessage = async (event) => {
    try {
      const msg = JSON.parse(event.nativeEvent.data || '{}');
      if (msg.type === 'openExternal' && msg.url) {
        try { await Linking.openURL(msg.url); } catch (e) { Alert.alert('ბმული ვერ გაიხსნა', 'შეამოწმე ბრაუზერი ან Google Maps-ის განახლება და ხელახლა სცადე.'); }
      }
      if (msg.type === 'openLocation435') {
        const lat = Number(msg.lat), lng = Number(msg.lng);
        if (msg.lat == null || msg.lng == null || !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat)>90 || Math.abs(lng)>180) return;
        const point = `${lat},${lng}`;
        const web = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(point)}`;
        try {
          await Linking.openURL(Platform.OS === 'android' ? `geo:0,0?q=${encodeURIComponent(point)}` : web);
        } catch (_) {
          try { await Linking.openURL(web); }
          catch (_) { Alert.alert('მდებარეობა ვერ გაიხსნა', 'შეამოწმე რუკის აპი ან ინტერნეტკავშირი და სცადე ხელახლა.'); }
        }
      }
      if (msg.type === 'openDailyCamera') {
        await openDailyCameraNative();
      }
      if (msg.type === 'registerPush') {
        pushController.current.request(msg.phone, {manual: !!msg.manual});
      }
      if (msg.type === 'pushRegistered' && msg.requestId === pushAck.current?.id) {
        pushAck.current.finish(msg.ok === true);
      }
      if (msg.type === 'unregisterPush') {
        pushController.current.stop();
        pushAck.current?.finish(false);
        if (pushTokenRef.current) webRef.current?.injectJavaScript(`sbRpc('unregister_push_device',{p_token:${JSON.stringify(pushTokenRef.current)}});true;`);
        pushTokenRef.current = '';
      }
      if (msg.type === 'setDailyPhotoReminder') {
        try {
          const result = await setDailyPhotoReminder(!!msg.enabled);
          if (result.denied) {
            webRef.current?.injectJavaScript(`dailyPhotoReminderEnabled=false; localStorage.setItem('chemiUbaniDailyPhotoReminder','off'); renderSettings(); alert('Notification permission არ არის ჩართული. შეგიძლია ჩართო ტელეფონის Settings-იდან.'); true;`);
          }
        } catch (e) {
          console.log('Photo reminder scheduling failed:', e?.message || e);
        }
      }
      if(msg.type === 'theme446') setDark446(msg.dark === true);
      if (msg.type === 'checkUpdate') {
        webRef.current?.injectJavaScript(`alert('განახლებები ახლა APK build-ით კეთდება. ახალი ვერსიისთვის დააყენე ბოლო APK.'); true;`);
      }
    } catch (_) {}
  };

  return (
    <SafeAreaView style={[styles.safe,dark446 && {backgroundColor:'#101b18'}]}>
      <StatusBar barStyle={dark446?'light-content':'dark-content'} />
      <View style={[styles.container,dark446 && {backgroundColor:'#101b18'}]}>
        <WebView
          key={webKey}
          ref={webRef}
          source={{ html: APP_HTML, baseUrl: 'https://chemi-ubani.local/' }}
          originWhitelist={['*']}
          javaScriptEnabled
          domStorageEnabled
          geolocationEnabled
          allowFileAccess
          allowUniversalAccessFromFileURLs
          mixedContentMode="always"
          setBuiltInZoomControls={false}
          setDisplayZoomControls={false}
          scalesPageToFit={false}
          setSupportMultipleWindows={false}
          javaScriptCanOpenWindowsAutomatically
          injectedJavaScriptBeforeContentLoaded={injected}
          onMessage={onMessage}
          onNavigationStateChange={(nav) => setCanGoBack(nav.canGoBack)}
          onLoadStart={() => { setLoading(true); setWebError(''); }}
          onLoadEnd={() => {
            webRef.current?.injectJavaScript(`window.appNativeActive=${AppState.currentState === 'active'};true;`);
            setLoading(false); webReady.current = true;
            if (pendingPushOpen.current) { webRef.current?.injectJavaScript(`window.handlePushOpen?.(${JSON.stringify(pendingPushOpen.current)}); true;`); pendingPushOpen.current = false; }
          }}
          onError={(e) => { setLoading(false); setWebError(e?.nativeEvent?.description || 'გვერდის ჩატვირთვა ვერ მოხერხდა'); }}
          onHttpError={(e) => { const code=e?.nativeEvent?.statusCode; if(code>=500) setWebError('სერვერი დროებით მიუწვდომელია'); }}
          keyboardDisplayRequiresUserAction={false}
          style={styles.web}
        />
        {loading && (
          <View style={styles.loader}>
            <Image source={require('./assets/icon.png')} style={styles.loaderLogo} />
            <ActivityIndicator size="large" />
            <Text style={styles.loaderText}>ჩემი უბანი</Text>
          </View>
        )}
        {!!webError && (
          <View style={styles.errorBox}>
            <Image source={require('./assets/icon.png')} style={styles.errorLogo} />
            <Text style={styles.errorTitle}>კავშირის პრობლემა</Text>
            <Text style={styles.errorText}>{webError}</Text>
            <TouchableOpacity style={styles.retryBtn} onPress={() => { setWebError(''); setWebKey(k => k + 1); }}>
              <Text style={styles.retryText}>თავიდან ცდა</Text>
            </TouchableOpacity>
          </View>
        )}

        <Modal visible={cameraOpen} animationType="slide" onRequestClose={closeDailyCamera} presentationStyle="fullScreen">
          <View style={styles.cameraShell}>
            {dailyBack && dailyFront ? (
              <View style={styles.cameraPreviewWrap}>
                <Image source={{ uri: dailyBack }} style={styles.cameraPreviewBack} />
                <Image source={{ uri: dailyFront }} style={styles.cameraPreviewFront} />
                <View style={styles.cameraPreviewActions}>
                  <ActivityIndicator color="#fff" />
                  <Text style={styles.cameraUseText}>ფოტოები მზადაა…</Text>
                </View>
              </View>
            ) : (
              <View style={styles.cameraShell}>
                {cameraOpen && <CameraView mute mode="picture" ref={cameraRef} style={StyleSheet.absoluteFill} facing={cameraFacing} onCameraReady={() => setCameraReady(true)} onMountError={() => Alert.alert('კამერის შეცდომა', 'კამერა ვერ გაეშვა. დახურე სხვა აპის კამერა და სცადე ხელახლა.')} />}
                <View style={styles.cameraTopBar}>
                  <TouchableOpacity style={styles.cameraRoundBtn} onPress={closeDailyCamera}><Text style={styles.cameraRoundText}>×</Text></TouchableOpacity>
                  <View style={styles.cameraStepPill}><Text style={styles.cameraStepText}>{cameraFacing === 'back' ? 'ერთი დაჭერა • ორივე კამერა' : 'მეორე კადრი ავტომატურად'}</Text></View>
                  <View style={{width:44}} />
                </View>
                {dailyBack && cameraFacing === 'front' && <Image source={{uri:dailyBack}} style={styles.cameraMiniBack} />}
                <View style={styles.cameraBottomBar}>
                  <Text style={styles.cameraHint}>{cameraFacing === 'back' ? 'დააჭირე ერთხელ — უკანა და წინა კადრი ავტომატურად გადაიღება' : 'არ გაინძრე • წინა კამერა ავტომატურად იღებს'}</Text>
                  <TouchableOpacity disabled={!cameraReady || captureBusy || (cameraFacing === 'front' && dualAutoCapture)} style={[styles.shutter,(!cameraReady||captureBusy||(cameraFacing === 'front'&&dualAutoCapture))&&{opacity:.5}]} onPress={captureDailyFrame}><View style={styles.shutterInner} /></TouchableOpacity>
                </View>
              </View>
            )}
          </View>
        </Modal>

      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f4f7f5' },
  container: { flex: 1, backgroundColor: '#f4f7f5' },
  web: { flex: 1, backgroundColor: '#f4f7f5' },
  loader: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', backgroundColor: '#f4f7f5' },
  loaderLogo: { width: 86, height: 86, borderRadius: 22, marginBottom: 18 },
  loaderText: { marginTop: 12, fontSize: 18, fontWeight: '800', color: '#087a4b' },
  errorBox: { ...StyleSheet.absoluteFillObject, alignItems: 'center', justifyContent: 'center', backgroundColor: '#f4f7f5', padding: 28 },
  errorLogo: { width: 72, height: 72, borderRadius: 18, marginBottom: 16 },
  errorTitle: { fontSize: 20, fontWeight: '900', color: '#17201b', marginBottom: 8 },
  errorText: { fontSize: 14, color: '#6d756f', textAlign: 'center', marginBottom: 18 },
  retryBtn: { backgroundColor: '#087a4b', paddingVertical: 12, paddingHorizontal: 22, borderRadius: 12 },
  retryText: { color: '#fff', fontWeight: '800' },
  cameraShell: { flex:1, backgroundColor:'#000' },
  cameraTopBar: { position:'absolute', top:45, left:18, right:18, flexDirection:'row', alignItems:'center', justifyContent:'space-between' },
  cameraRoundBtn: { width:44, height:44, borderRadius:22, backgroundColor:'rgba(0,0,0,.48)', alignItems:'center', justifyContent:'center' },
  cameraRoundText: { color:'#fff', fontSize:30, lineHeight:32 },
  cameraStepPill: { backgroundColor:'rgba(0,0,0,.52)', borderRadius:999, paddingVertical:9, paddingHorizontal:14 },
  cameraStepText: { color:'#fff', fontWeight:'800' },
  cameraBottomBar: { position:'absolute', bottom:40, left:0, right:0, alignItems:'center' },
  cameraHint: { color:'#fff', fontWeight:'800', marginBottom:18, backgroundColor:'rgba(0,0,0,.42)', paddingHorizontal:13, paddingVertical:8, borderRadius:999 },
  shutter: { width:80, height:80, borderRadius:40, borderWidth:5, borderColor:'#fff', alignItems:'center', justifyContent:'center' },
  shutterInner: { width:62, height:62, borderRadius:31, backgroundColor:'#fff' },
  cameraMiniBack: { position:'absolute', left:18, top:105, width:105, height:140, borderRadius:18, borderWidth:3, borderColor:'#fff' },
  cameraPreviewWrap: { flex:1, backgroundColor:'#000' },
  cameraPreviewBack: { flex:1, width:'100%', resizeMode:'cover' },
  cameraPreviewFront: { position:'absolute', left:20, top:70, width:125, height:165, borderRadius:20, borderWidth:4, borderColor:'#fff' },
  cameraPreviewActions: { position:'absolute', bottom:38, left:20, right:20, flexDirection:'row', gap:10 },
  cameraGhostBtn: { flex:1, padding:15, borderRadius:15, backgroundColor:'rgba(0,0,0,.6)', alignItems:'center' },
  cameraGhostText: { color:'#fff', fontWeight:'900' },
  cameraUseBtn: { flex:1.3, padding:15, borderRadius:15, backgroundColor:'#fff', alignItems:'center' },
  cameraUseText: { color:'#111', fontWeight:'900' }

});
