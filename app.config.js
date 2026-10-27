const fs = require('node:fs');
module.exports = ({ config }) => {
  const file = './config.public.local.json';
  const local = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
  return { ...config, extra: { ...config.extra, eas: {
    ...config.extra?.eas, projectId: local.expoProjectId || config.extra?.eas?.projectId
  } } };
};
