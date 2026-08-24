import {describe, test} from 'node:test';
import assert from 'node:assert/strict';
import {buildVanMenuTemplate, applyVanMenuState} from '../main/van-menu.js';

function createTemplate(disableUpdate = false)
{
	const noop = () => {};

	return buildVanMenuTemplate({
		appName: 'Van',
		dispatch: noop,
		showSettings: noop,
		openAbout: noop,
		openSupport: noop,
		checkForUpdates: {label: 'Check'},
		autoCheckForUpdates: {label: 'Automatic', type: 'checkbox'},
		setUpdateInterval: {label: 'Interval'},
		disableUpdate
	});
}

function findItem(items, predicate)
{
	for (const item of items)
	{
		if (predicate(item)) return item;
		const children = Array.isArray(item.submenu) ? item.submenu : [];
		const child = findItem(children, predicate);
		if (child != null) return child;
	}

	return null;
}

describe('Van native application menu', () =>
{
	test('contains the standard macOS menu groups and Settings shortcut', () =>
	{
		const template = createTemplate();
		assert.deepEqual(template.map((item) => item.label),
			['Van', 'File', 'Edit', 'Insert', 'View', 'Arrange', 'Window', 'Help']);

		const settings = findItem(template, (item) => item.label === 'Settings...');
		assert.equal(settings.accelerator, 'CommandOrControl+,');
	});

	test('exposes panel toggles as checked menu items', () =>
	{
		const template = createTemplate();
		assert.equal(findItem(template, (item) => item.id === 'van.action.toggleShapes').type, 'checkbox');
		assert.equal(findItem(template, (item) => item.id === 'van.action.format').type, 'checkbox');
		assert.equal(findItem(template, (item) => item.id === 'van.action.grid').type, 'checkbox');
	});

	test('omits updater controls when updates are disabled', () =>
	{
		const template = createTemplate(true);
		assert.equal(findItem(template, (item) => item.label === 'Check'), null);
		assert.equal(findItem(template, (item) => item.label === 'Settings...').accelerator,
			'CommandOrControl+,');
	});

	test('applies enabled and checked state by action id', () =>
	{
		const items = new Map([
			['van.action.undo', {type: 'normal', enabled: true}],
			['van.action.grid', {type: 'checkbox', enabled: true, checked: false}]
		]);
		const applicationMenu = {getMenuItemById: (id) => items.get(id)};

		applyVanMenuState(applicationMenu, {
			undo: {enabled: false},
			grid: {enabled: true, checked: true}
		});

		assert.equal(items.get('van.action.undo').enabled, false);
		assert.equal(items.get('van.action.grid').checked, true);
	});
});
