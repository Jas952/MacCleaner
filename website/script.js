const header = document.querySelector('[data-header]');
const menu = document.querySelector('[data-menu]');
const nav = document.querySelector('[data-nav]');
const hero = document.querySelector('[data-hero]');
const heroField = document.querySelector('.hero-field');
const macbookStage = document.querySelector('[data-macbook]');
const screenImages = [...document.querySelectorAll('[data-screen-image]')];
const screenTabs = [...document.querySelectorAll('[data-screen-tab]')];
const visibleTabs = screenTabs.filter((tab) => tab.getAttribute('role') === 'tab');
const previousButton = document.querySelector('[data-screen-prev]');
const nextButton = document.querySelector('[data-screen-next]');
const screenCounter = document.querySelector('[data-screen-count]');
const screenName = document.querySelector('[data-screen-name]');
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

const screens = [
  ['dashboard', 'Dashboard'],
  ['processes', 'Processes'],
  ['cooling', 'Fans / Cooling'],
  ['disk', 'Disk'],
  ['optimize', 'Optimize'],
  ['storage', 'Storage'],
  ['desktop', 'Desktop'],
  ['pake', 'Pake Apps'],
  ['agents', 'Agents'],
  ['library', 'Library'],
  ['tools', 'Tools'],
];

const syncHeader = () => header?.classList.toggle('scrolled', scrollY > 24);
syncHeader();
addEventListener('scroll', syncHeader, { passive: true });

menu?.addEventListener('click', () => {
  const isOpen = nav?.classList.toggle('open') ?? false;
  menu.setAttribute('aria-expanded', String(isOpen));
  menu.setAttribute('aria-label', isOpen ? 'Close menu' : 'Open menu');
  document.body.style.overflow = isOpen ? 'hidden' : '';
});

nav?.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => {
  nav.classList.remove('open');
  menu?.setAttribute('aria-expanded', 'false');
  menu?.setAttribute('aria-label', 'Open menu');
  document.body.style.overflow = '';
}));

let activeScreen = screens[0][0];
let transitionTimer;

const updateScreenMeta = (name) => {
  const index = screens.findIndex(([key]) => key === name);
  if (index < 0) return;
  screenCounter.textContent = `${String(index + 1).padStart(2, '0')} / ${String(screens.length).padStart(2, '0')}`;
  screenName.textContent = screens[index][1];
};

const showScreen = (name, focus = false) => {
  const nextIndex = screens.findIndex(([key]) => key === name);
  if (nextIndex < 0 || name === activeScreen) return;

  const previous = screenImages.find((image) => image.dataset.screenImage === activeScreen);
  const next = screenImages.find((image) => image.dataset.screenImage === name);
  const selectedTab = visibleTabs.find((tab) => tab.dataset.screenTab === name);
  if (!next || !selectedTab) return;

  activeScreen = name;
  hero.dataset.screen = name;
  clearTimeout(transitionTimer);
  screenTabs.forEach((tab) => {
    if (tab.getAttribute('role') === 'tab') tab.setAttribute('aria-selected', String(tab === selectedTab));
  });
  updateScreenMeta(name);

  next.hidden = false;
  requestAnimationFrame(() => {
    previous?.classList.remove('is-active');
    next.classList.add('is-active');
  });
  transitionTimer = setTimeout(() => {
    screenImages.forEach((image) => { if (image !== next) image.hidden = true; });
  }, 320);

  selectedTab.scrollIntoView({ behavior: reducedMotion.matches ? 'auto' : 'smooth', block: 'nearest', inline: 'center' });
  if (focus) selectedTab.focus();
};

const stepScreen = (direction) => {
  const currentIndex = screens.findIndex(([name]) => name === activeScreen);
  const nextIndex = (currentIndex + direction + screens.length) % screens.length;
  showScreen(screens[nextIndex][0], true);
};

screenTabs.forEach((tab) => {
  tab.addEventListener('click', () => showScreen(tab.dataset.screenTab));
  if (tab.getAttribute('role') !== 'tab') return;
  tab.addEventListener('keydown', (event) => {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    if (event.key === 'Home') return showScreen(screens[0][0], true);
    if (event.key === 'End') return showScreen(screens.at(-1)[0], true);
    stepScreen(event.key === 'ArrowRight' ? 1 : -1);
  });
});

previousButton?.addEventListener('click', () => stepScreen(-1));
nextButton?.addEventListener('click', () => stepScreen(1));

hero?.addEventListener('pointermove', (event) => {
  if (reducedMotion.matches || !matchMedia('(pointer: fine)').matches) return;
  const rect = hero.getBoundingClientRect();
  const x = (event.clientX - rect.left) / rect.width - .5;
  const y = (event.clientY - rect.top) / rect.height - .5;
  heroField.style.translate = `${(x * -15).toFixed(1)}px ${(y * -11).toFixed(1)}px`;
  macbookStage.style.transform = `rotateY(${(x * 1.05).toFixed(2)}deg) rotateX(${(y * -.45).toFixed(2)}deg)`;
});

hero?.addEventListener('pointerleave', () => {
  heroField.style.translate = '0 0';
  macbookStage.style.transform = '';
});

const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (!entry.isIntersecting) return;
    entry.target.classList.add('visible');
    revealObserver.unobserve(entry.target);
  });
}, { threshold: .08 });

document.querySelectorAll('.reveal').forEach((element) => revealObserver.observe(element));
updateScreenMeta(activeScreen);
