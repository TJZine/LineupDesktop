import type { RendererDomBindings } from './domBindings.js';
import type { SettingsSectionId } from './settingsSetup.js';
import type { RouteWorkflowViewModel } from './workflow.js';

export function renderSettingsDom(
  view: RouteWorkflowViewModel,
  dom: RendererDomBindings,
  activeSettingsCategory: SettingsSectionId,
): void {
  if (dom.settingsSourceElement) {
    dom.settingsSourceElement.textContent = view.settings.libraryName;
  }
  if (dom.settingsChannelsElement) {
    dom.settingsChannelsElement.textContent = String(view.settings.channelCount);
  }
  if (dom.settingsStateElement) {
    dom.settingsStateElement.textContent = `${view.settings.setupState}; ${view.settings.recoveryDetail}`;
  }

  // Update left category rail active states
  if (typeof document !== 'undefined' && typeof document.querySelectorAll === 'function') {
    const categoryButtons = document.querySelectorAll<HTMLButtonElement>('[data-settings-category]');
    for (const button of Array.from(categoryButtons)) {
      const isFocused = button.dataset.settingsCategory === activeSettingsCategory;
      button.classList.toggle('is-active', isFocused);
    }
  }

  if (dom.settingsSectionsElement) {
    dom.settingsSectionsElement.replaceChildren(
      ...view.settings.sections.map((section) => {
        const article = document.createElement('article');
        article.className = 'settings-section';
        article.dataset.settingsCategory = section.id;
        article.dataset.active = String(section.id === activeSettingsCategory);

        const title = document.createElement('h3');
        title.textContent = section.title;

        const detailText = document.createElement('p');
        detailText.className = 'settings-section-detail-text';
        detailText.textContent = section.detail;

        const itemsContainer = document.createElement('div');
        itemsContainer.className = 'settings-items-list';

        for (const setting of section.items) {
          // Determine if interactive and get action/focus-id mapping
          let action: string | null = null;
          let focusId: string | null = null;

          if (setting.id === 'launch-mode') {
            action = 'cycleLaunchMode';
            focusId = 'settings-launch-mode';
          } else if (setting.id === 'preview-badges') {
            action = 'togglePreviewBadges';
            focusId = 'settings-preview-badges';
          } else if (setting.id === 'guide-density') {
            action = 'cycleGuideDensity';
            focusId = 'settings-guide-density';
          } else if (setting.id === 'setup-reminder') {
            action = 'toggleSetupReminder';
            focusId = 'settings-setup-reminder';
          } else if (setting.id === 'support-bundle-export') {
            action = 'exportSupportBundle';
            focusId = 'settings-support-bundle';
          }

          if (action !== null && focusId !== null) {
            // Render as TV-style interactive button row
            const row = document.createElement('button');
            row.type = 'button';
            row.className = 'settings-control-row';
            row.dataset.settingsAction = action;
            row.dataset.focusId = focusId;

            const labelContainer = document.createElement('div');
            labelContainer.className = 'settings-control-row__label-container';
            const label = document.createElement('strong');
            label.textContent = setting.label;
            const desc = document.createElement('p');
            desc.textContent = setting.description;
            labelContainer.append(label, desc);

            const value = document.createElement('span');
            value.className = 'settings-control-row__value';
            value.textContent = setting.valueLabel;

            row.append(labelContainer, value);
            itemsContainer.append(row);
          } else {
            // Render as static information row
            const row = document.createElement('div');
            row.className = 'settings-info-row';

            const labelContainer = document.createElement('div');
            labelContainer.className = 'settings-info-row__label-container';
            const label = document.createElement('strong');
            label.textContent = setting.label;
            const desc = document.createElement('p');
            desc.textContent = setting.description;
            labelContainer.append(label, desc);

            const value = document.createElement('span');
            value.className = 'settings-info-row__value';
            value.textContent = setting.valueLabel;

            row.append(labelContainer, value);
            itemsContainer.append(row);
          }
        }

        article.append(title, detailText, itemsContainer);
        return article;
      }),
    );
  }
}
