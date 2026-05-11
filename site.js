const header = document.querySelector('[data-elevates]');
const copyButton = document.querySelector('[data-copy-target]');

const setHeaderState = () => {
  header?.classList.toggle('is-scrolled', window.scrollY > 24);
};

copyButton?.addEventListener('click', async () => {
  const targetId = copyButton.getAttribute('data-copy-target');
  const target = targetId ? document.getElementById(targetId) : null;
  const text = target?.innerText.trim();

  if (!text) return;

  try {
    await navigator.clipboard.writeText(text);
    copyButton.textContent = 'Copied';
    window.setTimeout(() => {
      copyButton.textContent = 'Copy';
    }, 1400);
  } catch {
    copyButton.textContent = 'Select text';
  }
});

setHeaderState();
window.addEventListener('scroll', setHeaderState, { passive: true });
