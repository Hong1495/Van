const {contextBridge, ipcRenderer} = require('electron');

contextBridge.exposeInMainWorld('vanSettings', {
	get: () => ipcRenderer.invoke('van-settings:get'),
	set: (key, value) => ipcRenderer.invoke('van-settings:set', {key, value}),
	openAdvanced: () => ipcRenderer.send('van-settings:open-advanced'),
	onChanged: (callback) => ipcRenderer.on('van-settings:changed', (event, settings) => callback(settings))
});
