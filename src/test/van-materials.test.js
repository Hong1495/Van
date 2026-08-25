import {describe, test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {
	getVanWindowFallbackColor,
	getVanWindowMaterialOptions
} from '../main/van-materials.js';

const vanCss = readFileSync(new URL(
	'../../drawio/src/main/webapp/styles/van.css', import.meta.url), 'utf8');
const vanRenderer = readFileSync(new URL(
	'../../drawio/src/main/webapp/js/diagramly/ElectronApp.js', import.meta.url), 'utf8');
const electronMain = readFileSync(new URL(
	'../main/electron.js', import.meta.url), 'utf8');

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

	test('adapts opaque shape-library previews to dark appearance', () =>
	{
		assert.match(vanCss,
			/\.geVan \.geMoreShapesPreview img\s*{[^}]*background:\s*transparent;/s);
		assert.match(vanCss,
			/body\.geVan\.geDarkMode \.geMoreShapesPreview img\s*{[^}]*filter:\s*invert\(/s);
	});

	test('keeps the native sidebar material stable when focus changes', () =>
	{
		assert.doesNotMatch(vanCss, /geVanMaterialFallback/);
		assert.doesNotMatch(vanRenderer, /geVanMaterialFallback/);
		assert.match(vanCss,
			/\.geVan > \.geSidebarContainer:not\(\.geFormatContainer\)\s*{[^}]*background:\s*var\(--van-sidebar-opaque\);/s);
		assert.doesNotMatch(vanCss,
			/\.geVan\.geVanNativeMaterial[^}]*background:\s*transparent;/s);
		assert.match(vanCss,
			/\.geEditor\.geVan\s*{[\s\S]*background:\s*var\(--van-workspace\);/s);
		assert.match(vanCss,
			/\.geVan > \.geHsplit\s*{[^}]*background:\s*var\(--van-workspace\);/s);
		assert.match(vanRenderer,
			/window\.addEventListener\('focus', updateVanWindowActivity\);[\s\S]*window\.addEventListener\('blur', updateVanWindowActivity\);/);
	});

	test('adds export between the fullscreen and inspector controls', () =>
	{
		assert.match(vanRenderer,
			/createMenuItem\('export', Editor\.saveImage\)/);
		assert.match(vanRenderer,
			/toolbarEnd\.insertBefore\(exportButton, toolbarEnd\.lastElementChild\)/);
	});

	test('keeps the shape library scrollable without a visible scrollbar', () =>
	{
		assert.match(vanCss,
			/\.geVan > \.geSidebarContainer:not\(\.geFormatContainer\) > div:first-child\s*{[^}]*scrollbar-width:\s*none;/s);
		assert.match(vanCss,
			/div:first-child::\-webkit-scrollbar\s*{[^}]*display:\s*none;/s);
	});

	test('finishes first-frame styling before revealing the editor window', () =>
	{
		const vanClass = vanRenderer.indexOf("document.body.classList.add('geVan')");
		const appLoadOverride = vanRenderer.indexOf('var appLoad = App.prototype.load');

		assert.ok(vanClass >= 0 && vanClass < appLoadOverride);
		assert.match(vanRenderer,
			/var vanStylesheetReady = new Promise\([\s\S]*vanStylesheet\.onload = resolve;[\s\S]*document\.head\.appendChild\(vanStylesheet\);/);
		assert.match(vanRenderer,
			/editorUi\.vanWorkspaceReady = vanSystemAppearancePromise\.then\([\s\S]*Promise\.all\(\[vanStylesheetReady, vanWorkspaceReady\]\)[\s\S]*\.then\(waitForVanFirstPaint\)\.then\(function\(\)[\s\S]*sendMessage\('app-load-finished'/);
		assert.match(vanRenderer,
			/var waitForVanFirstPaint = function\(\)[\s\S]*requestAnimationFrame\(function\(\)[\s\S]*requestAnimationFrame\(resolve\);/);
		assert.match(electronMain,
			/if \(!force && \(!browserReadyToShow \|\| !rendererReadyToShow\)\) return;/);
		assert.match(electronMain,
			/rendererReadyToShow = true;[\s\S]*mainWindow\.once\('ready-to-show',[\s\S]*browserReadyToShow = true;/);
	});
});
