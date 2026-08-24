import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const builderConfigs = [
	'electron-builder-linux-mac.json',
	'electron-builder-win.json',
	'electron-builder-win32.json',
	'electron-builder-win-arm64.json',
	'electron-builder-appx.json',
	'electron-builder-snap.json'
];

function readBuilderConfig(filename)
{
	return JSON.parse(fs.readFileSync(path.join(rootDir, filename), 'utf8'));
}

test('Van packaging keeps app branding and platform icons explicit', () =>
{
	for (const filename of builderConfigs)
	{
		const config = readBuilderConfig(filename);
		assert.equal(config.productName, 'Van', filename);
		assert.equal(config.appId, 'com.hong1495.van', filename);
	}

	const macConfig = readBuilderConfig('electron-builder-linux-mac.json');
	assert.equal(macConfig.mac.icon, './build/icon.icns');
	assert.equal(macConfig.linux.icon, './build');

	for (const filename of ['electron-builder-win.json', 'electron-builder-win32.json',
		'electron-builder-win-arm64.json', 'electron-builder-appx.json'])
	{
		assert.equal(readBuilderConfig(filename).win.icon, './build/icon.ico', filename);
	}

	assert.equal(macConfig.mac.extendInfo.UTExportedTypeDeclarations[0].UTTypeIdentifier,
		'com.hong1495.van.diagram');
	assert.equal(macConfig.mac.extendInfo.CFBundleDocumentTypes[0].CFBundleTypeName,
		'Van Diagram');
});
