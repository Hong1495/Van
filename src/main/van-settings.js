export const VAN_APPEARANCES = ['auto', 'light', 'dark'];
export const VAN_UPDATE_INTERVALS = [24, 48, 72, 168];

export function sanitizeVanSetting(key, value)
{
	switch (key)
	{
		case 'appearance':
			return VAN_APPEARANCES.includes(value) ? value : null;
		case 'spellCheck':
		case 'automaticBackup':
		case 'googleFonts':
		case 'automaticUpdates':
		case 'autosave':
			return typeof value === 'boolean' ? value : null;
		case 'updateIntervalHours':
			return VAN_UPDATE_INTERVALS.includes(Number(value)) ? Number(value) : null;
		case 'draftSaveDelay':
		{
			const delay = Number(value);
			return Number.isInteger(delay) && delay >= 0 && delay <= 3600 ? delay : null;
		}
		default:
			return null;
	}
}
