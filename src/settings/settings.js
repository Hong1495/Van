const fields = {
	autosave: document.getElementById('autosave'),
	automaticUpdates: document.getElementById('automaticUpdates'),
	updateIntervalHours: document.getElementById('updateIntervalHours'),
	spellCheck: document.getElementById('spellCheck'),
	automaticBackup: document.getElementById('automaticBackup'),
	draftSaveDelay: document.getElementById('draftSaveDelay'),
	googleFonts: document.getElementById('googleFonts')
};

let applyingState = false;
let statusTimer = null;

function applySystemAppearance(appearance)
{
	if (appearance == null) return;

	const root = document.documentElement;
	root.classList.toggle('native-vibrancy', appearance.nativeVibrancy === true);
	root.classList.toggle('reduce-transparency', appearance.reducedTransparency === true);
	root.classList.toggle('high-contrast', appearance.highContrast === true);
	root.classList.toggle('differentiate-without-color',
		appearance.differentiateWithoutColor === true);

	if (appearance.colors != null)
	{
		const colors = appearance.colors;
		const properties = {
			selectionBackground: '--selected',
			selectionText: '--selected-text',
			unemphasizedSelectionBackground: '--selected-inactive',
			separator: '--system-line'
		};

		for (const [key, property] of Object.entries(properties))
		{
			if (typeof colors[key] === 'string' && /^#[0-9a-f]{8}$/i.test(colors[key]))
			{
				root.style.setProperty(property, colors[key]);
			}
		}
	}
}

function updateWindowActivity()
{
	document.documentElement.classList.toggle('window-inactive', !document.hasFocus());
}

function showSaved()
{
	const status = document.getElementById('saveStatus');
	status.textContent = 'Saved';
	window.clearTimeout(statusTimer);
	statusTimer = window.setTimeout(() => { status.textContent = ''; }, 1200);
}

function applySettings(settings)
{
	if (settings == null)
	{
		return;
	}

	applyingState = true;

	for (const [key, field] of Object.entries(fields))
	{
		if (settings[key] != null)
		{
			if (field.type === 'checkbox')
			{
				field.checked = settings[key];
			}
			else
			{
				field.value = settings[key];
			}
		}
	}

	const appearance = document.querySelector(`input[name="appearance"][value="${settings.appearance}"]`);

	if (appearance != null)
	{
		appearance.checked = true;
	}

	fields.updateIntervalHours.disabled = settings.automaticUpdates === false;
	applyingState = false;
}

async function persist(key, value)
{
	if (applyingState)
	{
		return;
	}

	const result = await window.vanSettings.set(key, value);
	applySettings(result);
	showSaved();
}

document.querySelectorAll('.nav-item').forEach((button) =>
{
	button.addEventListener('click', () =>
	{
		document.querySelector('.nav-item.is-selected')?.classList.remove('is-selected');
		document.querySelector('.settings-section.is-active')?.classList.remove('is-active');
		button.classList.add('is-selected');
		document.querySelector(`[data-panel="${button.dataset.section}"]`)?.classList.add('is-active');
	});
});

for (const [key, field] of Object.entries(fields))
{
	field.addEventListener('change', () =>
	{
		const value = field.type === 'checkbox' ? field.checked :
			(field.type === 'number' || key === 'updateIntervalHours' ? Number(field.value) : field.value);
		void persist(key, value);
	});
}

document.querySelectorAll('input[name="appearance"]').forEach((radio) =>
{
	radio.addEventListener('change', () =>
	{
		if (radio.checked)
		{
			void persist('appearance', radio.value);
		}
	});
});

document.getElementById('openAdvanced').addEventListener('click', () =>
{
	window.vanSettings.openAdvanced();
});

window.vanSettings.onChanged(applySettings);
window.vanSettings.onSystemAppearance(applySystemAppearance);
window.vanSettings.get().then(applySettings);
window.vanSettings.getSystemAppearance().then(applySystemAppearance);
window.addEventListener('focus', updateWindowActivity);
window.addEventListener('blur', updateWindowActivity);
updateWindowActivity();
