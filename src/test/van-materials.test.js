import {describe, test} from 'node:test';
import assert from 'node:assert/strict';
import {
	getVanWindowFallbackColor,
	getVanWindowMaterialOptions
} from '../main/van-materials.js';

describe('Van macOS window materials', () =>
{
	test('uses a transparent native sidebar material on macOS', () =>
	{
		assert.deepEqual(getVanWindowMaterialOptions({
			isMac: true,
			kind: 'editor',
			dark: false,
			reducedTransparency: false
		}), {
			backgroundColor: '#00000000',
			transparent: true,
			vibrancy: 'sidebar',
			visualEffectState: 'followWindow'
		});
	});

	test('falls back to an opaque semantic background when transparency is reduced', () =>
	{
		assert.deepEqual(getVanWindowMaterialOptions({
			isMac: true,
			kind: 'settings',
			dark: true,
			reducedTransparency: true
		}), {
			backgroundColor: '#252527',
			transparent: true
		});
	});

	test('keeps non-macOS windows opaque', () =>
	{
		assert.deepEqual(getVanWindowMaterialOptions({
			isMac: false,
			kind: 'editor',
			dark: false,
			reducedTransparency: false
		}), {backgroundColor: '#E6E7E9'});
		assert.equal(getVanWindowFallbackColor('settings', false), '#FFFFFF');
	});
});
