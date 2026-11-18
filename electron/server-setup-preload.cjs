/*
 * Preload for the Server Address window (fork, remote-server mode). Its whole
 * API: read the current server, save one, go back to local, close. Main
 * validates everything (normalizeServer) and only answers this window.
 */
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("lhServerSetup", {
	get: () => ipcRenderer.invoke("lh:server-setup", { op: "get" }),
	save: (url) => ipcRenderer.invoke("lh:server-setup", { op: "save", url: String(url) }),
	useLocal: () => ipcRenderer.invoke("lh:server-setup", { op: "local" }),
	cancel: () => ipcRenderer.invoke("lh:server-setup", { op: "cancel" }),
});
