import {describe, test} from 'node:test';
import assert from 'node:assert/strict';
import {buildVanContextMenuTemplate} from '../main/van-context-menu.js';

describe('Van native context menu bridge', () =>
{
	test('preserves commands, checks, disabled state and submenus', () =>
	{
		let selected = null;
		const template = buildVanContextMenuTemplate([
			{label: 'Paste Here', token: 'paste', enabled: false},
			{type: 'separator'},
			{label: 'Grid', token: 'grid', checked: true},
			{label: 'Arrange', submenu: [{label: 'Front', token: 'front'}]}
		], (token) => { selected = token; });

		assert.equal(template[0].enabled, false);
		assert.equal(template[2].type, 'checkbox');
		assert.equal(template[2].checked, true);
		assert.equal(template[3].submenu[0].label, 'Front');
		template[3].submenu[0].click();
		assert.equal(selected, 'front');
	});

	test('drops malformed entries and redundant separators', () =>
	{
		const template = buildVanContextMenuTemplate([
			{type: 'separator'},
			null,
			{label: ''},
			{label: 'Select All', token: 'all'},
			{type: 'separator'},
			{type: 'separator'}
		], () => {});

		assert.deepEqual(template.map((item) => item.type || item.label), ['Select All']);
	});
});
