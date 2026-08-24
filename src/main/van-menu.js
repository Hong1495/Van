const actionItemId = (action) => `van.action.${action}`;

export const VAN_NATIVE_ACTIONS = [
	'new', 'open', 'save', 'saveAs', 'import', 'export', 'pageSetup', 'print',
	'undo', 'redo', 'cut', 'copy', 'paste', 'pasteHere', 'delete', 'duplicate',
	'findReplace', 'editData', 'editStyle', 'editLink', 'selectAll', 'selectNone',
	'insertText', 'insertRectangle', 'insertEllipse', 'insertEdge', 'image', 'link',
	'insertTemplate', 'toggleShapes', 'format', 'layers', 'outline', 'grid', 'guides',
	'pageView', 'pageTabs', 'ruler', 'tooltips', 'animations', 'resetView', 'fitWindow',
	'fitPage', 'fitPageWidth', 'zoomIn', 'zoomOut', 'toFront', 'toBack',
	'bringForward', 'sendBackward', 'group', 'ungroup', 'lockUnlock',
	'alignCellsLeft', 'alignCellsCenter', 'alignCellsRight', 'alignCellsTop',
	'alignCellsMiddle', 'alignCellsBottom', 'distributeHorizontal',
	'distributeVertical', 'help'
];

function actionItem(dispatch, label, action, options = {})
{
	return {
		id: actionItemId(action),
		label,
		click: () => dispatch(action),
		...options
	};
}

export function buildVanMenuTemplate({
	appName,
	dispatch,
	showSettings,
	openAbout,
	openSupport,
	checkForUpdates,
	autoCheckForUpdates,
	setUpdateInterval,
	disableUpdate = false
})
{
	const appSubmenu = [
		{label: `About ${appName}`, click: openAbout},
		{label: 'Settings...', accelerator: 'CommandOrControl+,', click: showSettings},
		{type: 'separator'}
	];

	if (!disableUpdate)
	{
		appSubmenu.push(checkForUpdates, autoCheckForUpdates, setUpdateInterval,
			{type: 'separator'});
	}

	appSubmenu.push(
		{label: 'Support', click: openSupport},
		{type: 'separator'},
		{role: 'services'},
		{type: 'separator'},
		{role: 'hide'},
		{role: 'hideOthers'},
		{role: 'unhide'},
		{type: 'separator'},
		{role: 'quit'}
	);

	return [
		{
			label: appName,
			submenu: appSubmenu
		},
		{
			label: 'File',
			submenu: [
				actionItem(dispatch, 'New', 'new', {accelerator: 'CommandOrControl+N'}),
				actionItem(dispatch, 'Open...', 'open', {accelerator: 'CommandOrControl+O'}),
				{type: 'separator'},
				actionItem(dispatch, 'Save', 'save', {accelerator: 'CommandOrControl+S'}),
				actionItem(dispatch, 'Save As...', 'saveAs', {accelerator: 'CommandOrControl+Shift+S'}),
				{type: 'separator'},
				actionItem(dispatch, 'Import...', 'import'),
				actionItem(dispatch, 'Export...', 'export'),
				{type: 'separator'},
				actionItem(dispatch, 'Page Setup...', 'pageSetup'),
				actionItem(dispatch, 'Print...', 'print', {accelerator: 'CommandOrControl+P'}),
				{type: 'separator'},
				{role: 'close'}
			]
		},
		{
			label: 'Edit',
			submenu: [
				actionItem(dispatch, 'Undo', 'undo', {accelerator: 'CommandOrControl+Z'}),
				actionItem(dispatch, 'Redo', 'redo', {accelerator: 'CommandOrControl+Shift+Z'}),
				{type: 'separator'},
				actionItem(dispatch, 'Cut', 'cut', {accelerator: 'CommandOrControl+X'}),
				actionItem(dispatch, 'Copy', 'copy', {accelerator: 'CommandOrControl+C'}),
				actionItem(dispatch, 'Paste', 'paste', {accelerator: 'CommandOrControl+V'}),
				actionItem(dispatch, 'Paste Here', 'pasteHere'),
				actionItem(dispatch, 'Delete', 'delete', {accelerator: 'Backspace'}),
				actionItem(dispatch, 'Duplicate', 'duplicate', {accelerator: 'CommandOrControl+D'}),
				{type: 'separator'},
				actionItem(dispatch, 'Find and Replace...', 'findReplace', {accelerator: 'CommandOrControl+F'}),
				actionItem(dispatch, 'Edit Data...', 'editData'),
				actionItem(dispatch, 'Edit Style...', 'editStyle'),
				actionItem(dispatch, 'Edit Link...', 'editLink'),
				{type: 'separator'},
				actionItem(dispatch, 'Select All', 'selectAll', {accelerator: 'CommandOrControl+A'}),
				actionItem(dispatch, 'Select None', 'selectNone', {accelerator: 'CommandOrControl+Shift+A'})
			]
		},
		{
			label: 'Insert',
			submenu: [
				actionItem(dispatch, 'Text', 'insertText'),
				actionItem(dispatch, 'Rectangle', 'insertRectangle'),
				actionItem(dispatch, 'Ellipse', 'insertEllipse'),
				actionItem(dispatch, 'Line', 'insertEdge'),
				{type: 'separator'},
				actionItem(dispatch, 'Image...', 'image'),
				actionItem(dispatch, 'Link...', 'link'),
				actionItem(dispatch, 'Template...', 'insertTemplate')
			]
		},
		{
			label: 'View',
			submenu: [
				actionItem(dispatch, 'Show Library', 'toggleShapes', {type: 'checkbox', accelerator: 'CommandOrControl+Shift+K'}),
				actionItem(dispatch, 'Show Inspector', 'format', {type: 'checkbox', accelerator: 'CommandOrControl+Shift+P'}),
				{type: 'separator'},
				actionItem(dispatch, 'Layers', 'layers'),
				actionItem(dispatch, 'Outline', 'outline'),
				{type: 'separator'},
				actionItem(dispatch, 'Grid', 'grid', {type: 'checkbox', accelerator: 'CommandOrControl+Shift+G'}),
				actionItem(dispatch, 'Guides', 'guides', {type: 'checkbox'}),
				actionItem(dispatch, 'Page View', 'pageView', {type: 'checkbox'}),
				actionItem(dispatch, 'Page Tabs', 'pageTabs', {type: 'checkbox'}),
				actionItem(dispatch, 'Ruler', 'ruler', {type: 'checkbox'}),
				actionItem(dispatch, 'Tooltips', 'tooltips', {type: 'checkbox'}),
				actionItem(dispatch, 'Animations', 'animations', {type: 'checkbox'}),
				{type: 'separator'},
				actionItem(dispatch, 'Actual Size', 'resetView', {accelerator: 'CommandOrControl+0'}),
				actionItem(dispatch, 'Zoom In', 'zoomIn', {accelerator: 'CommandOrControl+='}),
				actionItem(dispatch, 'Zoom Out', 'zoomOut', {accelerator: 'CommandOrControl+-'}),
				actionItem(dispatch, 'Fit Window', 'fitWindow'),
				actionItem(dispatch, 'Fit Page', 'fitPage'),
				actionItem(dispatch, 'Fit Page Width', 'fitPageWidth'),
				{type: 'separator'},
				{role: 'togglefullscreen'}
			]
		},
		{
			label: 'Arrange',
			submenu: [
				actionItem(dispatch, 'Bring to Front', 'toFront'),
				actionItem(dispatch, 'Send to Back', 'toBack'),
				actionItem(dispatch, 'Bring Forward', 'bringForward'),
				actionItem(dispatch, 'Send Backward', 'sendBackward'),
				{type: 'separator'},
				actionItem(dispatch, 'Group', 'group', {accelerator: 'CommandOrControl+G'}),
				actionItem(dispatch, 'Ungroup', 'ungroup', {accelerator: 'CommandOrControl+Shift+U'}),
				actionItem(dispatch, 'Lock / Unlock', 'lockUnlock'),
				{type: 'separator'},
				{
					label: 'Align',
					submenu: [
						actionItem(dispatch, 'Left', 'alignCellsLeft'),
						actionItem(dispatch, 'Center', 'alignCellsCenter'),
						actionItem(dispatch, 'Right', 'alignCellsRight'),
						actionItem(dispatch, 'Top', 'alignCellsTop'),
						actionItem(dispatch, 'Middle', 'alignCellsMiddle'),
						actionItem(dispatch, 'Bottom', 'alignCellsBottom')
					]
				},
				{
					label: 'Distribute',
					submenu: [
						actionItem(dispatch, 'Horizontally', 'distributeHorizontal'),
						actionItem(dispatch, 'Vertically', 'distributeVertical')
					]
				}
			]
		},
		{
			label: 'Window',
			submenu: [
				{role: 'minimize'},
				{role: 'zoom'},
				{type: 'separator'},
				{role: 'front'}
			]
		},
		{
			label: 'Help',
			submenu: [
				actionItem(dispatch, `${appName} Help`, 'help'),
				{label: 'Report an Issue...', click: openSupport}
			]
		}
	];
}

export function applyVanMenuState(applicationMenu, actionState)
{
	if (applicationMenu == null || actionState == null)
	{
		return;
	}

	for (const action of VAN_NATIVE_ACTIONS)
	{
		const item = applicationMenu.getMenuItemById(actionItemId(action));
		const state = actionState[action];

		if (item != null && state != null)
		{
			item.enabled = state.enabled !== false;

			if (item.type === 'checkbox' && typeof state.checked === 'boolean')
			{
				item.checked = state.checked;
			}
		}
	}
}
