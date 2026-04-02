import { CapacitorConfig } from '@capacitor/cli';

const serverUrl = process.env.CAP_SERVER_URL?.trim() || 'https://matterya.com';

const config: CapacitorConfig = {
  appId: 'com.worldapp.mobile',
  appName: 'World App',
  webDir: '../web/dist/web/browser',
  server: {
    url: serverUrl,
    cleartext: false
  }
};

export default config;
