const WINDOW_FALLBACKS = {
	editor: {
		light: '#E6E7E9',
		dark: '#19191B'
	},
	settings: {
		light: '#FFFFFF',
		dark: '#252527'
	}
};

export function getVanWindowFallbackColor(kind, dark)
{
	const palette = WINDOW_FALLBACKS[kind] || WINDOW_FALLBACKS.editor;
	return dark ? palette.dark : palette.light;
}

export function getVanWindowMaterialOptions({isMac, kind, dark, reducedTransparency})
{
	const backgroundColor = getVanWindowFallbackColor(kind, dark);

	if (!isMac)
	{
		return {backgroundColor};
	}

	return {
		backgroundColor: reducedTransparency ? backgroundColor : '#00000000',
		transparent: true,
		...(reducedTransparency ? {} : {
			vibrancy: 'sidebar',
			visualEffectState: 'followWindow'
		})
	};
}
