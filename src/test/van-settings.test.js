import {describe, test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {sanitizeVanSetting} from '../main/van-settings.js';

const settingsRenderer = readFileSync(new URL('../settings/settings.js', import.meta.url), 'utf8');
const settingsPreload = readFileSync(new URL('../main/settings-preload.js', import.meta.url), 'utf8');
const electronMain = readFileSync(new URL('../main/electron.js', import.meta.url), 'utf8');

describe('Van settings validation', () =>
{
	test('accepts only system, light and dark appearance values', () =>
	{
		assert.equal(sanitizeVanSetting('appearance', 'auto'), 'auto');
		assert.equal(sanitizeVanSetting('appearance', 'light'), 'light');
		assert.equal(sanitizeVanSetting('appearance', 'dark'), 'dark');
		assert.equal(sanitizeVanSetting('appearance', 'sketch'), null);
		assert.equal(sanitizeVanSetting('appearance', 'high-contrast'), null);
	});

	test('rejects invalid boolean, interval and draft values', () =>
	{
		assert.equal(sanitizeVanSetting('spellCheck', true), true);
		assert.equal(sanitizeVanSetting('spellCheck', 'true'), null);
		assert.equal(sanitizeVanSetting('updateIntervalHours', 168), 168);
		assert.equal(sanitizeVanSetting('updateIntervalHours', 12), null);
		assert.equal(sanitizeVanSetting('draftSaveDelay', 0), 0);
		assert.equal(sanitizeVanSetting('draftSaveDelay', 3601), null);
	});

	test('reveals settings only after values and appearance are ready', () =>
	{
		assert.match(settingsPreload,
			/ready:\s*\(\) => ipcRenderer\.send\('van-settings:ready'\)/);
		assert.match(settingsRenderer,
			/Promise\.all\(\[initialSettingsReady, initialAppearanceReady\]\)[\s\S]*window\.vanSettings\.ready\(\)/);
		assert.match(electronMain,
			/if \(browserReady && rendererReady &&[\s\S]*pendingSettingsWindow\.show\(\)/);
		assert.match(electronMain,
			/ipcMain\.on\('van-settings:ready', handleSettingsReady\)[\s\S]*settingsWindow\.once\('ready-to-show'/);
		assert.match(electronMain,
			/if \(settingsWindow\.vanReadyToShow\)[\s\S]*settingsWindow\.show\(\)/);
	});

	test('scopes editor readiness events to their owning window', () =>
	{
		assert.doesNotMatch(electronMain,
			/ipcMain\.once\('app-load-finished'/);
		assert.match(electronMain,
			/e\.sender !== win\.webContents \|\|[\s\S]*ipcMain\.removeListener\('app-load-finished', loadFinished\)/);
	});
});
