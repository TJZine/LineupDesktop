import type { RendererDomBindings } from './domBindings.js';
import type { SettingsSectionId } from './settingsSetup.js';
import type { RouteWorkflowViewModel } from './workflow.js';

export function renderSettingsProfileDom(profileName: string | null, documentRef: Document): void {
  const element = documentRef.querySelector<HTMLElement>('[data-settings-profile-name]');
  if (element !== null) element.textContent = profileName ?? 'No profile selected.';
}

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
        const isActive = section.id === activeSettingsCategory;
        article.className = 'settings-section';
        article.dataset.settingsCategory = section.id;
        article.dataset.active = String(isActive);
        article.hidden = !isActive;
        if (isActive) article.removeAttribute('inert');
        else article.setAttribute('inert', '');
        article.setAttribute('aria-hidden', String(!isActive));

        const title = document.createElement('h3');
        title.textContent = section.title;

        const detailText = document.createElement('p');
        detailText.className = 'settings-section-detail-text';
        detailText.textContent = section.detail;

        const itemsContainer = document.createElement('div');
        itemsContainer.className = 'settings-items-list';

        for (const setting of section.items) {
          const action = setting.action ?? null;
          const focusId = action === null ? null : `settings-${setting.id}`;

          if (action !== null && focusId !== null) {
            // Render as TV-style interactive button row
            const row = document.createElement('button');
            row.type = 'button';
            row.className = 'settings-control-row';
            row.dataset.settingsAction = action;
            row.dataset.focusId = focusId;
            row.disabled = setting.disabled === true || (
              document.documentElement.dataset.settingsSaving === 'true' &&
              action !== 'exportSupportBundle'
            );
            row.setAttribute('aria-disabled', String(row.disabled));
            if (setting.disabledReason !== undefined) {
              row.dataset.disabledReason = setting.disabledReason;
            }

            const labelContainer = document.createElement('div');
            labelContainer.className = 'settings-control-row__label-container';
            const label = document.createElement('strong');
            label.textContent = setting.label;
            const desc = document.createElement('p');
            desc.textContent = setting.disabledReason === undefined
              ? setting.description
              : `${setting.description} ${setting.disabledReason}`;
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
