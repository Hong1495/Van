const {contextBridge, ipcRenderer} = require('electron');

contextBridge.exposeInMainWorld('vanSettings', {
	get: () => ipcRenderer.invoke('van-settings:get'),
	getSystemAppearance: () => ipcRenderer.invoke('van-system-appearance:get'),
	set: (key, value) => ipcRenderer.invoke('van-settings:set', {key, value}),
	ready: () => ipcRenderer.send('van-settings:ready'),
	openAdvanced: () => ipcRenderer.send('van-settings:open-advanced'),
	onChanged: (callback) => ipcRenderer.on('van-settings:changed', (event, settings) => callback(settings)),
	onSystemAppearance: (callback) => ipcRenderer.on('van-system-appearance',
		(event, appearance) => callback(appearance))
});
