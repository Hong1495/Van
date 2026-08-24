import {describe, test} from 'node:test';
import assert from 'node:assert/strict';
import {sanitizeVanSetting} from '../main/van-settings.js';

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
});
