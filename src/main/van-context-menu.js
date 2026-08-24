const MAX_MENU_DEPTH = 2;
const MAX_MENU_ITEMS = 160;

function sanitizeText(value, maxLength)
{
	return typeof value === 'string' ? value.slice(0, maxLength) : '';
}

function sanitizeMenuItems(items, onSelect, depth, count)
{
	if (!Array.isArray(items) || depth > MAX_MENU_DEPTH) return [];

	const result = [];

	for (const item of items)
	{
		if (count.value >= MAX_MENU_ITEMS) break;
		if (item == null || typeof item !== 'object') continue;
		count.value++;

		if (item.type === 'separator')
		{
			if (result.length > 0 && result[result.length - 1].type !== 'separator')
			{
				result.push({type: 'separator'});
			}

			continue;
		}

		const label = sanitizeText(item.label, 180);

		if (label.length === 0) continue;

		const submenu = sanitizeMenuItems(item.submenu, onSelect, depth + 1, count);
		const token = sanitizeText(item.token, 80);
		const menuItem = {
			label,
			enabled: item.enabled !== false
		};

		if (submenu.length > 0)
		{
			menuItem.submenu = submenu;
		}
		else if (item.checked === true)
		{
			menuItem.type = 'checkbox';
			menuItem.checked = true;
		}

		if (token.length > 0 && submenu.length === 0)
		{
			menuItem.click = () => onSelect(token);
		}

		result.push(menuItem);
	}

	while (result.length > 0 && result[result.length - 1].type === 'separator')
	{
		result.pop();
	}

	return result;
}

export function buildVanContextMenuTemplate(items, onSelect)
{
	return sanitizeMenuItems(items, onSelect, 0, {value: 0});
}
