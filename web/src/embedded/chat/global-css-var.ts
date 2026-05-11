const GlobalCSSVars = {
  activityCenterHeight: '--activity-center-height',
  colorPrimary: '--color-primary',
  colorPrimaryHighlight: '--color-primary-highlight',
};

const defaultValues: Partial<Record<keyof typeof GlobalCSSVars, string>> = {
  activityCenterHeight: '0px',
};

export const commitGlobalCSSVar = (
  key: keyof typeof GlobalCSSVars,
  value?: string
) => {
  const varName = GlobalCSSVars[key];
  if (!value) {
    document.body.style.removeProperty(varName);
  } else {
    document.body.style.setProperty(varName, value);
  }
};

export const globalVar = (
  key: keyof typeof GlobalCSSVars,
  fallback?: string
) => {
  const name = GlobalCSSVars[key];
  const defaultValue = defaultValues[key];
  if (!fallback && !defaultValue) {
    return `var(${name})`;
  }
  return `var(${name}, ${fallback ?? defaultValue})`;
};
